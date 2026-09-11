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

    func stub() throws -> StubHTTPClient {
        let http = StubHTTPClient()
        http.on(path: "/watch", body: try Fixture.data("watch-page-snippet.html"))
        http.on(path: "/youtubei/v1/player", body: try Fixture.data("player-ciphered.json"))
        http.on(path: "/iframe_api", body: try Fixture.data("iframe-api-snippet.js"))
        http.on(pathSuffix: "/base.js", body: Data("var player = 1; signatureTimestamp:20312".utf8))
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
}
