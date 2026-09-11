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
    public let bitrate: Int
    public let width: Int?
    public let height: Int?
    public let fps: Int?
    public let url: URL
    public let nChallenge: String?
    public let signatureChallenge: SignatureChallenge?

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
            bitrate: raw.bitrate ?? 0,
            width: raw.width,
            height: raw.height,
            fps: raw.fps,
            url: url,
            nChallenge: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "n" }?.value,
            signatureChallenge: signature
        )
    }

    /// Returns a copy with solved challenges applied to the URL, or nil if a needed solution is missing.
    func resolvingChallenges(_ solved: [ChallengeKind: [String: String]]) -> StreamFormat? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var items = components.percentEncodedQueryItems ?? []

        if let n = nChallenge {
            guard let solvedN = solved[.n]?[n], !solvedN.isEmpty,
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
            itag: itag, kind: kind, container: container, codec: codec, bitrate: bitrate,
            width: width, height: height, fps: fps, url: rewritten,
            nChallenge: nil, signatureChallenge: nil
        )
    }

    private static func percentEncoded(_ value: String) -> String? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)
    }
}
