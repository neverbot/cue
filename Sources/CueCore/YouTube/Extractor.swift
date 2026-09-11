import Foundation

public struct Resolution: Sendable {
    public let videoID: VideoID
    public let title: String
    public let author: String?
    public let duration: TimeInterval?
    public let selection: FormatSelection
    public let formats: [StreamFormat]
    public let hlsManifestURL: URL?
    public let captionTrackCount: Int
    public let storyboardSpec: String?
    /// Stream requests must use this User-Agent.
    public let userAgent: String
}

public enum ExtractionError: Error, Equatable, Sendable {
    case httpStatus(Int, URL)
    case visitorDataNotFound
    case unexpectedResponse
    case unplayable(status: String, reason: String?)
    case noPlayableFormats
    case challengeSolverUnavailable
    case playerScriptNotFound
    case unsolvedChallenges
}

extension ExtractionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .httpStatus(status, url): "YouTube returned HTTP \(status) for \(url.absoluteString)."
        case .visitorDataNotFound: "The YouTube watch page did not include visitor data."
        case .unexpectedResponse: "YouTube returned a response Cue could not read."
        case let .unplayable(status, reason): "This video can't be played: \(reason ?? status)."
        case .noPlayableFormats: "No stream this Mac can decode efficiently was found."
        case .challengeSolverUnavailable: "This video needs YouTube's player challenges solved, but the solver is unavailable."
        case .playerScriptNotFound: "YouTube's player script could not be located."
        case .unsolvedChallenges: "YouTube's player challenges could not be solved."
        }
    }
}

public struct Extractor: Sendable {
    let http: any HTTPClient
    let client: ClientProfile
    let selector: FormatSelector
    let solver: ChallengeSolver?

    public init(
        http: any HTTPClient = URLSessionHTTPClient(session: URLSession(configuration: .ephemeral)),
        client: ClientProfile = .visionOS,
        selector: FormatSelector = FormatSelector(),
        solver: ChallengeSolver? = try? ChallengeSolver.bundled()
    ) {
        self.http = http
        self.client = client
        self.selector = selector
        self.solver = solver
    }

    public func resolve(_ videoID: VideoID) async throws -> Resolution {
        let watchURL = WatchPage.url(for: videoID)
        let page = try await http.send(HTTPRequest(url: watchURL, headers: ["User-Agent": client.userAgent, "Cookie": WatchPage.consentCookie]))
        guard page.status == 200 else { throw ExtractionError.httpStatus(page.status, watchURL) }
        guard let visitorData = WatchPage.visitorData(in: String(decoding: page.body, as: UTF8.self)) else {
            throw ExtractionError.visitorDataNotFound
        }

        let request = try InnerTube.playerRequest(videoID: videoID, client: client, visitorData: visitorData, signatureTimestamp: nil)
        let response = try await http.send(request)
        guard response.status == 200 else { throw ExtractionError.httpStatus(response.status, request.url) }

        let player: PlayerResponse
        do {
            player = try JSONDecoder().decode(PlayerResponse.self, from: response.body)
        } catch {
            throw ExtractionError.unexpectedResponse
        }
        guard player.playabilityStatus.status == "OK" else {
            throw ExtractionError.unplayable(status: player.playabilityStatus.status, reason: player.playabilityStatus.reason)
        }

        var formats = (player.streamingData?.adaptiveFormats ?? []).compactMap(StreamFormat.init(raw:))
        if formats.contains(where: \.needsChallenges) {
            formats = try await solveChallenges(in: formats)
        }
        guard let selection = selector.select(from: formats) else { throw ExtractionError.noPlayableFormats }

        return Resolution(
            videoID: videoID,
            title: player.videoDetails?.title ?? videoID.rawValue,
            author: player.videoDetails?.author,
            duration: player.videoDetails?.lengthSeconds.flatMap(TimeInterval.init),
            selection: selection,
            formats: formats,
            hlsManifestURL: player.streamingData?.hlsManifestUrl.flatMap(URL.init(string:)),
            captionTrackCount: player.captions?.playerCaptionsTracklistRenderer?.captionTracks?.count ?? 0,
            storyboardSpec: player.storyboards?.playerStoryboardSpecRenderer?.spec,
            userAgent: client.userAgent
        )
    }

    private func solveChallenges(in formats: [StreamFormat]) async throws -> [StreamFormat] {
        guard let solver else { throw ExtractionError.challengeSolverUnavailable }

        let iframe = try await http.send(HTTPRequest(url: PlayerScript.iframeAPIURL, headers: ["User-Agent": client.userAgent]))
        guard iframe.status == 200,
              let playerID = PlayerScript.playerID(inIframeAPI: String(decoding: iframe.body, as: UTF8.self))
        else { throw ExtractionError.playerScriptNotFound }

        let baseURL = PlayerScript.baseJSURL(playerID: playerID)
        let base = try await http.send(HTTPRequest(url: baseURL, headers: ["User-Agent": client.userAgent]))
        guard base.status == 200 else { throw ExtractionError.httpStatus(base.status, baseURL) }

        let challenges: [ChallengeKind: [String]] = [
            .n: Array(Set(formats.compactMap(\.nChallenge))).sorted(),
            .sig: Array(Set(formats.compactMap { $0.signatureChallenge?.encrypted })).sorted(),
        ]
        let solved = try solver.solve(playerID: playerID, playerJS: String(decoding: base.body, as: UTF8.self), challenges: challenges)

        let resolved = formats.compactMap { $0.needsChallenges ? $0.resolvingChallenges(solved) : $0 }
        guard !resolved.isEmpty else { throw ExtractionError.unsolvedChallenges }
        return resolved
    }
}
