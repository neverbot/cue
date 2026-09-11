import Foundation
import Testing
@testable import CueCore

@Suite struct ExtractorChallengeTests {
    let videoID = VideoID("dQw4w9WgXcQ")!
    let selector = FormatSelector(maxHeight: 1080, av1HardwareDecoding: false)

    static let reversingCore = """
    var jsc = (input) => ({
      type: 'result',
      responses: input.requests.map((r) => ({
        type: 'result',
        data: Object.fromEntries(r.challenges.map((c) => [c, c.split('').reverse().join('')])),
      })),
    });
    """

    static let emptyCore = """
    var jsc = (input) => ({
      type: 'result',
      responses: input.requests.map((r) => ({
        type: 'result',
        data: Object.fromEntries(r.challenges.map((c) => [c, ''])),
      })),
    });
    """

    /// Solves n challenges but returns an empty signature, so only the ciphered video format is dropped.
    static let unsolvedSignatureCore = """
    var jsc = (input) => ({
      type: 'result',
      responses: input.requests.map((r) => ({
        type: 'result',
        data: Object.fromEntries(r.challenges.map((c) => [c, r.type === 'n' ? c.split('').reverse().join('') : ''])),
      })),
    });
    """

    func stub(iframeStatus: Int = 200, baseStatus: Int = 200) throws -> StubHTTPClient {
        let http = StubHTTPClient()
        http.on(path: "/watch", body: try Fixture.data("watch-page-snippet.html"))
        http.on(path: "/youtubei/v1/player", body: try Fixture.data("player-ciphered.json"))
        http.on(path: "/iframe_api", status: iframeStatus, body: try Fixture.data("iframe-api-snippet.js"))
        http.on(pathSuffix: "/base.js", status: baseStatus, body: Data("var player = 1; signatureTimestamp:20312".utf8))
        return http
    }

    @Test func rewritesCipheredStreams() async throws {
        let http = try stub()
        let solver = ChallengeSolver(libSource: "var lib = {};", coreSource: Self.reversingCore)

        let resolution = try await Extractor(http: http, selector: selector, solver: solver).resolve(videoID)

        #expect(resolution.selection.video.url.absoluteString == "https://rr1.googlevideo.com/videoplayback?itag=137&n=cba&expire=1&sig=FEDCBA")
        #expect(resolution.selection.audio.url.absoluteString == "https://rr1.googlevideo.com/videoplayback?itag=140&n=zyx&expire=1")
        #expect(http.recorded.map(\.url.path) == ["/watch", "/youtubei/v1/player", "/iframe_api", "/s/player/8c3fda2d/player_ias.vflset/en_US/base.js"])
    }

    @Test func failsWithoutSolver() async throws {
        let http = try stub()
        await #expect(throws: ExtractionError.challengeSolverUnavailable) {
            try await Extractor(http: http, selector: selector, solver: nil).resolve(videoID)
        }
    }

    @Test func failsWhenPlayerScriptCannotBeFound() async throws {
        let http = StubHTTPClient()
        http.on(path: "/watch", body: try Fixture.data("watch-page-snippet.html"))
        http.on(path: "/youtubei/v1/player", body: try Fixture.data("player-ciphered.json"))
        http.on(path: "/iframe_api", body: Data("no player here".utf8))
        let solver = ChallengeSolver(libSource: "var lib = {};", coreSource: Self.reversingCore)

        await #expect(throws: ExtractionError.playerScriptNotFound) {
            try await Extractor(http: http, selector: selector, solver: solver).resolve(videoID)
        }
    }

    @Test func failsWhenChallengesStayUnsolved() async throws {
        let http = try stub()
        let solver = ChallengeSolver(libSource: "var lib = {};", coreSource: Self.emptyCore)

        await #expect(throws: ExtractionError.unsolvedChallenges) {
            try await Extractor(http: http, selector: selector, solver: solver).resolve(videoID)
        }
    }

    @Test func propagatesSolverErrors() async throws {
        let http = try stub()
        let solver = ChallengeSolver(libSource: "var lib = {};", coreSource: "var jsc = () => { throw new Error('boom'); };")

        await #expect(throws: ChallengeSolverError.javaScriptException("Error: boom")) {
            try await Extractor(http: http, selector: selector, solver: solver).resolve(videoID)
        }
    }

    @Test func reportsUnsolvedChallengesWhenOneKindIsDropped() async throws {
        let http = try stub()
        let solver = ChallengeSolver(libSource: "var lib = {};", coreSource: Self.unsolvedSignatureCore)

        await #expect(throws: ExtractionError.unsolvedChallenges) {
            try await Extractor(http: http, selector: selector, solver: solver).resolve(videoID)
        }
    }

    @Test func reportsIframeAPIHTTPErrors() async throws {
        let http = try stub(iframeStatus: 503)
        let solver = ChallengeSolver(libSource: "var lib = {};", coreSource: Self.reversingCore)

        await #expect(throws: ExtractionError.httpStatus(503, PlayerScript.iframeAPIURL)) {
            try await Extractor(http: http, selector: selector, solver: solver).resolve(videoID)
        }
    }

    @Test func reportsPlayerScriptHTTPErrors() async throws {
        let http = try stub(baseStatus: 404)
        let solver = ChallengeSolver(libSource: "var lib = {};", coreSource: Self.reversingCore)

        await #expect(throws: ExtractionError.httpStatus(404, PlayerScript.baseJSURL(playerID: "8c3fda2d"))) {
            try await Extractor(http: http, selector: selector, solver: solver).resolve(videoID)
        }
    }

    @Test func reportsNoPlayableFormatsWhenDroppedFormatsWouldNotHelp() async throws {
        let player = #"{"playabilityStatus":{"status":"OK"},"streamingData":{"adaptiveFormats":[{"itag":248,"mimeType":"video/webm; codecs=\"vp09.00.40.08\"","bitrate":2000000,"height":1080,"url":"https://rr1.googlevideo.com/videoplayback?itag=248"},{"itag":140,"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":130000,"url":"https://rr1.googlevideo.com/videoplayback?itag=140&n=xyz"}]}}"#
        let http = StubHTTPClient()
        http.on(path: "/watch", body: try Fixture.data("watch-page-snippet.html"))
        http.on(path: "/youtubei/v1/player", body: Data(player.utf8))
        http.on(path: "/iframe_api", body: try Fixture.data("iframe-api-snippet.js"))
        http.on(pathSuffix: "/base.js", body: Data("var player = 1;".utf8))
        let solver = ChallengeSolver(libSource: "var lib = {};", coreSource: Self.emptyCore)

        await #expect(throws: ExtractionError.noPlayableFormats) {
            try await Extractor(http: http, selector: selector, solver: solver).resolve(videoID)
        }
    }
}
