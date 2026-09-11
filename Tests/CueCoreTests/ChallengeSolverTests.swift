import Foundation
import Testing
@testable import CueCore

@Suite struct ChallengeSolverTests {
    static let reverseLib = "var lib = { reverse: (s) => s.split('').reverse().join('') };"

    /// Mimics the EJS core contract: reverses n challenges; answers sig challenges with the input type.
    static let reverseCore = """
    var jsc = (input) => {
      const out = {
        type: 'result',
        responses: input.requests.map((r) => ({
          type: 'result',
          data: Object.fromEntries(r.challenges.map((c) => [c, r.type === 'n' ? reverse(c) : input.type])),
        })),
      };
      if (input.type === 'player' && input.output_preprocessed) { out.preprocessed_player = 'pre:' + input.player; }
      return out;
    };
    """

    @Test func solvesThroughJavaScriptCore() throws {
        let solver = ChallengeSolver(libSource: Self.reverseLib, coreSource: Self.reverseCore)
        let solved = try solver.solve(playerID: "p1", playerJS: "player-code", challenges: [.n: ["abc", "xyz"]])
        #expect(solved[.n] == ["abc": "cba", "xyz": "zyx"])
    }

    @Test func cachesThePreprocessedPlayer() throws {
        let solver = ChallengeSolver(libSource: Self.reverseLib, coreSource: Self.reverseCore)
        let first = try solver.solve(playerID: "p1", playerJS: "player-code", challenges: [.sig: ["s"]])
        let second = try solver.solve(playerID: "p1", playerJS: "player-code", challenges: [.sig: ["s"]])
        #expect(first[.sig] == ["s": "player"])
        #expect(second[.sig] == ["s": "preprocessed"])
    }

    @Test func surfacesSolverErrors() throws {
        let core = "var jsc = (input) => ({ type: 'result', responses: input.requests.map(() => ({ type: 'error', error: 'Failed to extract n function' })) });"
        let solver = ChallengeSolver(libSource: Self.reverseLib, coreSource: core)
        #expect(throws: ChallengeSolverError.solverFailed(kind: "n", message: "Failed to extract n function")) {
            try solver.solve(playerID: "p1", playerJS: "x", challenges: [.n: ["abc"]])
        }
    }

    @Test func surfacesJavaScriptExceptions() throws {
        let solver = ChallengeSolver(libSource: Self.reverseLib, coreSource: "var jsc = () => { throw new Error('boom'); };")
        #expect(throws: ChallengeSolverError.javaScriptException("Error: boom")) {
            try solver.solve(playerID: "p1", playerJS: "x", challenges: [.n: ["abc"]])
        }
    }

    @Test func loadsBundledScripts() throws {
        _ = try ChallengeSolver.bundled()
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CUE_LIVE_TESTS"] == "1"))
    func solvesAgainstTheLiveYouTubePlayer() async throws {
        let http = URLSessionHTTPClient()
        let iframe = try await http.send(HTTPRequest(url: PlayerScript.iframeAPIURL))
        let playerID = try #require(PlayerScript.playerID(inIframeAPI: String(decoding: iframe.body, as: UTF8.self)))
        let base = try await http.send(HTTPRequest(url: PlayerScript.baseJSURL(playerID: playerID)))
        let solver = try ChallengeSolver.bundled()
        let solved = try solver.solve(playerID: playerID, playerJS: String(decoding: base.body, as: UTF8.self), challenges: [.n: ["0aBcDeFgHiJkLmNoP"]])
        let output = try #require(solved[.n]?["0aBcDeFgHiJkLmNoP"])
        #expect(!output.isEmpty)
        #expect(output != "0aBcDeFgHiJkLmNoP")
    }
}
