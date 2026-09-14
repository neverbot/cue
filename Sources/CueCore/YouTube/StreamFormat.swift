import Foundation

/// Kinds of JavaScript challenges YouTube attaches to stream URLs.
public enum ChallengeKind: String, Sendable, CaseIterable {
    case n
    case sig
}

/// One adaptive stream (video-only or audio-only).
public struct StreamFormat: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case video
        case audio
    }

    public struct SignatureChallenge: Sendable, Equatable {
        public let encrypted: String
        public let parameter: String
    }

    public let itag: Int
    public let kind: Kind
    public let container: String
    public let codec: String
    /// Bit depth from the codecs string for AV1/VP9 (10 means HDR on YouTube); nil when not stated.
    public let bitDepth: Int?
    public let bitrate: Int
    public let width: Int?
    public let height: Int?
    public let fps: Int?
    public let url: URL
    public let nChallenge: String?
    public let signatureChallenge: SignatureChallenge?
    /// The language this audio format carries, on the videos that offer dubs. Nil on every video format, and on
    /// every format of a video with a single soundtrack.
    public let audioTrack: AudioTrack?

    public init(
        itag: Int,
        kind: Kind,
        container: String,
        codec: String,
        bitDepth: Int?,
        bitrate: Int,
        width: Int?,
        height: Int?,
        fps: Int?,
        url: URL,
        nChallenge: String?,
        signatureChallenge: SignatureChallenge?,
        audioTrack: AudioTrack? = nil
    ) {
        self.itag = itag
        self.kind = kind
        self.container = container
        self.codec = codec
        self.bitDepth = bitDepth
        self.bitrate = bitrate
        self.width = width
        self.height = height
        self.fps = fps
        self.url = url
        self.nChallenge = nChallenge
        self.signatureChallenge = signatureChallenge
        self.audioTrack = audioTrack
    }

    public var needsChallenges: Bool { nChallenge != nil || signatureChallenge != nil }
}

extension StreamFormat {
    init?(raw: PlayerResponse.RawFormat) {
        guard let mimeType = raw.mimeType else { return nil }
        let mimeParts = mimeType.split(separator: ";", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let mediaType = mimeParts.first else { return nil }
        let typeParts = mediaType.split(separator: "/").map(String.init)
        guard typeParts.count == 2 else { return nil }

        let kind: Kind
        switch typeParts[0] {
        case "video": kind = .video
        case "audio": kind = .audio
        default: return nil
        }

        let codecs = mimeParts.count > 1 ? (firstCapture(#"codecs="([^"]+)""#, in: mimeParts[1]) ?? "") : ""
        let codecPrefix = String(codecs.split(separator: ".").first ?? "")
        let codec = codecPrefix == "vp09" ? "vp9" : codecPrefix

        var urlString = raw.url
        var signature: SignatureChallenge?
        if urlString == nil, let cipher = raw.signatureCipher {
            let items = URLComponents(string: "?" + cipher)?.queryItems ?? []
            urlString = items.first { $0.name == "url" }?.value
            if let encrypted = items.first(where: { $0.name == "s" })?.value {
                let parameter = items.first { $0.name == "sp" }?.value ?? ""
                signature = SignatureChallenge(encrypted: encrypted, parameter: parameter.isEmpty ? "signature" : parameter)
            }
        }
        guard let urlString, let url = URL(string: urlString), url.scheme == "https", url.host() != nil else { return nil }

        self.init(
            itag: raw.itag,
            kind: kind,
            container: typeParts[1],
            codec: codec,
            bitDepth: Self.bitDepth(fromCodecs: codecs),
            bitrate: raw.bitrate ?? 0,
            width: raw.width,
            height: raw.height,
            fps: raw.fps,
            url: url,
            nChallenge: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "n" }?.value,
            signatureChallenge: signature,
            audioTrack: AudioTrack(raw: raw.audioTrack)
        )
    }

    /// Returns a copy with solved challenges applied to the URL, or nil if a needed solution is missing.
    func resolvingChallenges(_ solved: [ChallengeKind: [String: String]]) -> StreamFormat? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var items = components.percentEncodedQueryItems ?? []

        if let n = nChallenge {
            guard let solvedN = solved[.n]?[n], !solvedN.isEmpty,
                  items.filter({ $0.name == "n" }).count == 1,
                  let index = items.firstIndex(where: { $0.name == "n" }),
                  let encodedN = Self.percentEncoded(solvedN), !encodedN.isEmpty
            else { return nil }
            items[index] = URLQueryItem(name: "n", value: encodedN)
        }
        if let signature = signatureChallenge {
            guard let solvedSignature = solved[.sig]?[signature.encrypted], !solvedSignature.isEmpty,
                  let encodedName = Self.percentEncoded(signature.parameter), !encodedName.isEmpty,
                  !items.contains(where: { $0.name == encodedName }),
                  let encodedValue = Self.percentEncoded(solvedSignature), !encodedValue.isEmpty
            else { return nil }
            items.append(URLQueryItem(name: encodedName, value: encodedValue))
        }
        components.percentEncodedQueryItems = items
        guard let rewritten = components.url else { return nil }

        return StreamFormat(
            itag: itag, kind: kind, container: container, codec: codec, bitDepth: bitDepth, bitrate: bitrate,
            width: width, height: height, fps: fps, url: rewritten,
            nChallenge: nil, signatureChallenge: nil, audioTrack: audioTrack
        )
    }

    /// `av01.P.LLT.DD` and `vp09.PP.LL.DD…` carry the bit depth in the fourth field.
    static func bitDepth(fromCodecs codecs: String) -> Int? {
        let parts = codecs.split(separator: ".")
        guard parts.count >= 4, parts[0] == "av01" || parts[0] == "vp09" else { return nil }
        return Int(parts[3])
    }

    private static func percentEncoded(_ value: String) -> String? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)
    }
}
