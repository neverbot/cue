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
    case challengesUnsupported
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
        solver: ChallengeSolver? = nil
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

        let formats = (player.streamingData?.adaptiveFormats ?? []).compactMap(StreamFormat.init(raw:))
        guard !formats.contains(where: \.needsChallenges) else { throw ExtractionError.challengesUnsupported }
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
}
