import Foundation
import os

private let logger = Logger(subsystem: "com.neverbot.cue", category: "extraction")

public struct Resolution: Sendable {
    public let videoID: VideoID
    public let title: String
    public let author: String?
    public let duration: TimeInterval?
    /// The video's own sections, empty when it has none.
    public let chapters: [Chapter]
    public let selection: FormatSelection
    /// Playable formats: unciphered formats plus ciphered formats in the selector's acceptable set, with their challenges solved.
    public let formats: [StreamFormat]
    /// The audio languages this video offers, with the stream each plays from. Empty for a video with one
    /// soundtrack. All of them come from this one response, so switching between them costs no further request.
    public let audioTracks: [AudioTrackOption]
    public let hlsManifestURL: URL?
    public let captionTracks: [CaptionTrack]
    /// The seek-bar preview sheets, when YouTube offers them.
    public let storyboard: StoryboardSpec?
    /// When the stream URLs stop working; re-resolve before then.
    public let expiresAt: Date?
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
    /// Loaded once so every extractor shares the scripts and the solver's preprocessed-player cache.
    public static let bundledSolver: ChallengeSolver? = try? ChallengeSolver.bundled()

    let http: any HTTPClient
    let client: ClientProfile
    let selector: FormatSelector
    let solver: ChallengeSolver?
    let now: @Sendable () -> Date

    public init(
        http: any HTTPClient = URLSessionHTTPClient(session: URLSession(configuration: .ephemeral)),
        client: ClientProfile = .visionOS,
        selector: FormatSelector = FormatSelector(),
        solver: ChallengeSolver? = Extractor.bundledSolver,
        now: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.http = http
        self.client = client
        self.selector = selector
        self.solver = solver
        self.now = now
    }

    public func resolve(_ videoID: VideoID) async throws -> Resolution {
        let requestedAt = now()
        let watchURL = WatchPage.url(for: videoID)
        let page = try await http.send(HTTPRequest(url: watchURL, headers: ["User-Agent": client.userAgent, "Cookie": WatchPage.consentCookie]))
        guard page.status == 200 else { throw ExtractionError.httpStatus(page.status, watchURL) }
        let html = String(decoding: page.body, as: UTF8.self)
        guard let visitorData = WatchPage.visitorData(in: html) else {
            throw ExtractionError.visitorDataNotFound
        }

        let request = try InnerTube.playerRequest(videoID: videoID, client: client, visitorData: visitorData, signatureTimestamp: nil)
        let response = try await http.send(request)
        guard response.status == 200 else { throw ExtractionError.httpStatus(response.status, request.url) }

        let player: PlayerResponse
        do {
            player = try JSONDecoder().decode(PlayerResponse.self, from: response.body)
        } catch {
            // The /player response is the owner's own data, and carries the signed stream URLs and caption
            // baseUrls. A corrupted-data error can quote the bytes around the failure, so this stays private.
            logger.error("Undecodable /player response for \(videoID.rawValue, privacy: .private): \(String(describing: error), privacy: .private)")
            throw ExtractionError.unexpectedResponse
        }
        guard player.playabilityStatus.status == "OK" else {
            throw ExtractionError.unplayable(status: player.playabilityStatus.status, reason: player.playabilityStatus.reason)
        }

        let offered = (player.streamingData?.adaptiveFormats ?? []).compactMap(StreamFormat.init(raw:))
        var formats = offered
        if offered.contains(where: \.needsChallenges) {
            formats = try await solveChallenges(in: offered)
        }
        guard let selection = selector.select(from: formats) else {
            // Blame unsolved challenges only when the formats they cost could have been selected.
            throw selector.select(from: offered) != nil ? ExtractionError.unsolvedChallenges : ExtractionError.noPlayableFormats
        }

        let duration = player.videoDetails?.lengthSeconds.flatMap(TimeInterval.init)
        // The page's markers are what the video says about itself; its description is the fallback for the many
        // videos whose chapters were only ever written there.
        let marked = WatchPageChapters.chapters(inHTML: html, duration: duration)
        let chapters = marked.isEmpty
            ? Chapter.list(inDescription: player.videoDetails?.shortDescription ?? "", duration: duration)
            : marked

        return Resolution(
            videoID: videoID,
            title: player.videoDetails?.title ?? videoID.rawValue,
            author: player.videoDetails?.author,
            duration: duration,
            chapters: chapters,
            selection: selection,
            formats: formats,
            audioTracks: selector.audioTrackOptions(from: formats),
            hlsManifestURL: player.streamingData?.hlsManifestUrl.flatMap(URL.init(string:)),
            captionTracks: CaptionTrack.list(in: player.captions),
            storyboard: player.storyboards?.playerStoryboardSpecRenderer?.spec.flatMap(StoryboardSpec.init),
            expiresAt: player.streamingData?.expiresInSeconds.flatMap(TimeInterval.init).map { requestedAt.addingTimeInterval($0) },
            userAgent: client.userAgent
        )
    }

    private func solveChallenges(in formats: [StreamFormat]) async throws -> [StreamFormat] {
        let acceptable = selector.acceptableFormats(from: formats)
        let candidates = acceptable.filter(\.needsChallenges)
        guard !candidates.isEmpty else { return formats.filter { !$0.needsChallenges } }

        guard let solver else { throw ExtractionError.challengeSolverUnavailable }

        let iframe = try await http.send(HTTPRequest(url: PlayerScript.iframeAPIURL, headers: ["User-Agent": client.userAgent]))
        guard iframe.status == 200 else { throw ExtractionError.httpStatus(iframe.status, PlayerScript.iframeAPIURL) }
        guard let playerID = PlayerScript.playerID(inIframeAPI: String(decoding: iframe.body, as: UTF8.self)) else {
            throw ExtractionError.playerScriptNotFound
        }

        let baseURL = PlayerScript.baseJSURL(playerID: playerID)
        let challenges: [ChallengeKind: [String]] = [
            .n: Array(Set(candidates.compactMap(\.nChallenge))).sorted(),
            .sig: Array(Set(candidates.compactMap { $0.signatureChallenge?.encrypted })).sorted(),
        ]
        let solved = try await solver.solve(playerID: playerID, challenges: challenges) { [http, client] in
            let base = try await http.send(HTTPRequest(url: baseURL, headers: ["User-Agent": client.userAgent]))
            guard base.status == 200 else { throw ExtractionError.httpStatus(base.status, baseURL) }
            return String(decoding: base.body, as: UTF8.self)
        }

        return formats.compactMap { !$0.needsChallenges ? $0 : (acceptable.contains($0) ? $0.resolvingChallenges(solved) : nil) }
    }
}
