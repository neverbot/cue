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

    /// The vendored scripts in the source tree, so tests do not depend on how resource bundles are located.
    static let scriptsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/CueCore/Resources/ejs")

    static func reverseSolver() -> ChallengeSolver {
        ChallengeSolver(libSource: reverseLib, coreSource: reverseCore)
    }

    @Test func solvesThroughJavaScriptCore() throws {
        let solved = try Self.reverseSolver().solve(playerID: "p1", playerJS: "player-code", challenges: [.n: ["abc", "xyz"]])
        #expect(solved[.n] == ["abc": "cba", "xyz": "zyx"])
    }

    @Test func solvesMixedRequestsInOrder() throws {
        let solved = try Self.reverseSolver().solve(playerID: "p1", playerJS: "player-code", challenges: [.sig: ["s"], .n: ["abc"]])
        #expect(solved[.n] == ["abc": "cba"])
        #expect(solved[.sig] == ["s": "player"])
    }

    @Test func skipsJavaScriptWithoutChallenges() throws {
        let solver = ChallengeSolver(libSource: Self.reverseLib, coreSource: "throw new Error('should not run');")
        #expect(try solver.solve(playerID: "p1", playerJS: "x", challenges: [.n: [], .sig: []]).isEmpty)
    }

    @Test func cachesThePreprocessedPlayer() throws {
        let solver = Self.reverseSolver()
        let first = try solver.solve(playerID: "p1", playerJS: "player-code", challenges: [.sig: ["s"]])
        let second = try solver.solve(playerID: "p1", playerJS: "player-code", challenges: [.sig: ["s"]])
        #expect(first[.sig] == ["s": "player"])
        #expect(second[.sig] == ["s": "preprocessed"])
    }

    @Test func keysTheCacheByPlayerID() throws {
        let solver = Self.reverseSolver()
        _ = try solver.solve(playerID: "p1", playerJS: "one", challenges: [.sig: ["s"]])
        #expect(try solver.solve(playerID: "p2", playerJS: "two", challenges: [.sig: ["s"]])[.sig] == ["s": "player"])
        #expect(try solver.solve(playerID: "p1", playerJS: "one", challenges: [.sig: ["s"]])[.sig] == ["s": "preprocessed"])
    }

    @Test func keepsOnlyRecentPlayersCached() throws {
        let solver = Self.reverseSolver()
        for id in ["p1", "p2", "p3"] {
            _ = try solver.solve(playerID: id, playerJS: id, challenges: [.sig: ["s"]])
        }
        #expect(try solver.solve(playerID: "p3", playerJS: "p3", challenges: [.sig: ["s"]])[.sig] == ["s": "preprocessed"])
        #expect(try solver.solve(playerID: "p1", playerJS: "p1", challenges: [.sig: ["s"]])[.sig] == ["s": "player"])
    }

    @Test func solvesConcurrently() throws {
        let solver = Self.reverseSolver()
        let results = DispatchQueue.concurrentPerformResults(count: 8) { index in
            try? solver.solve(playerID: "p\(index % 2)", playerJS: "x", challenges: [.n: ["abc\(index)"]])[.n]
        }
        for (index, result) in results.enumerated() {
            #expect(result == ["abc\(index)": "\(index)cba"])
        }
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

    @Test func reportsTheFirstJavaScriptException() throws {
        let solver = ChallengeSolver(libSource: "var lib = {", coreSource: Self.reverseCore)
        let error = #expect(throws: ChallengeSolverError.self) {
            try solver.solve(playerID: "p1", playerJS: "x", challenges: [.n: ["abc"]])
        }
        guard case let .javaScriptException(message)? = error else {
            Issue.record("expected a JavaScript exception, got \(String(describing: error))")
            return
        }
        #expect(message.contains("SyntaxError"))
    }

    @Test(arguments: [
        "var jsc = () => 'nope';",
        "var jsc = () => ({ type: 'result', responses: [] });",
        "var jsc = (input) => ({ type: 'result', responses: input.requests.map(() => ({ type: 'result', data: { abc: 1 } })) });",
    ])
    func rejectsMalformedOutput(core: String) throws {
        let solver = ChallengeSolver(libSource: Self.reverseLib, coreSource: core)
        #expect(throws: ChallengeSolverError.malformedOutput) {
            try solver.solve(playerID: "p1", playerJS: "x", challenges: [.n: ["abc"]])
        }
    }

    @Test func throwsWhenScriptsAreMissing() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(throws: ChallengeSolverError.scriptsMissing) {
            try ChallengeSolver(scriptsDirectory: missing)
        }
    }

    @Test func runsTheVendoredScriptsOffline() throws {
        let solver = try ChallengeSolver(scriptsDirectory: Self.scriptsDirectory)
        let error = #expect(throws: ChallengeSolverError.self) {
            try solver.solve(playerID: "p1", playerJS: "var x = 1;", challenges: [.n: ["abc"]])
        }
        guard case let .javaScriptException(message)? = error else {
            Issue.record("expected a JavaScript exception, got \(String(describing: error))")
            return
        }
        #expect(message.contains("unexpected structure"))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CUE_LIVE_TESTS"] == "1"))
    func solvesAgainstTheLiveYouTubePlayer() async throws {
        let http = URLSessionHTTPClient()
        let iframe = try await http.send(HTTPRequest(url: PlayerScript.iframeAPIURL))
        let playerID = try #require(PlayerScript.playerID(inIframeAPI: String(decoding: iframe.body, as: UTF8.self)))
        let base = try await http.send(HTTPRequest(url: PlayerScript.baseJSURL(playerID: playerID)))
        let solver = try ChallengeSolver(scriptsDirectory: Self.scriptsDirectory)
        let solved = try solver.solve(playerID: playerID, playerJS: String(decoding: base.body, as: UTF8.self), challenges: [.n: ["0aBcDeFgHiJkLmNoP"]])
        let output = try #require(solved[.n]?["0aBcDeFgHiJkLmNoP"])
        #expect(!output.isEmpty)
        #expect(output != "0aBcDeFgHiJkLmNoP")
    }
}

private extension DispatchQueue {
    static func concurrentPerformResults<T: Sendable>(count: Int, _ body: @Sendable (Int) -> T) -> [T] {
        let lock = NSLock()
        nonisolated(unsafe) var results = [T?](repeating: nil, count: count)
        concurrentPerform(iterations: count) { index in
            let value = body(index)
            lock.withLock { results[index] = value }
        }
        return results.map { $0! }
    }
}
