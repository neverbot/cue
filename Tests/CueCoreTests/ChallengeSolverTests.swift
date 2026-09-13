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

    @Test func fallsBackToThePinnedPlayerAfterEviction() throws {
        let solver = Self.reverseSolver()
        _ = try solver.solve(playerID: "p1", playerJS: "one", challenges: [.sig: ["s"]])
        let pinned = try #require(solver.cachedPlayer("p1"))
        for id in ["p2", "p3"] {
            _ = try solver.solve(playerID: id, playerJS: id, challenges: [.sig: ["s"]])
        }
        #expect(!solver.hasPreprocessedPlayer("p1"))

        let solved = try solver.solve(playerID: "p1", playerJS: "", challenges: [.sig: ["s"]], pinnedPreprocessed: pinned)
        #expect(solved[.sig] == ["s": "preprocessed"])
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
        #expect(throws: ChallengeSolverError.solverFailed(kind: .n, message: "Failed to extract n function")) {
            try solver.solve(playerID: "p1", playerJS: "x", challenges: [.n: ["abc"]])
        }
    }

    @Test func surfacesJavaScriptExceptions() throws {
        let solver = ChallengeSolver(libSource: Self.reverseLib, coreSource: "var jsc = () => { throw new Error('boom'); };")
        #expect(throws: ChallengeSolverError.javaScriptException("Error: boom")) {
            try solver.solve(playerID: "p1", playerJS: "x", challenges: [.n: ["abc"]])
        }
    }

    @Test func describesErrorsReadably() {
        #expect((ChallengeSolverError.scriptsMissing as any Error).localizedDescription == "Cue's challenge solver scripts are missing.")
        #expect((ChallengeSolverError.javaScriptException("Error: boom") as any Error).localizedDescription == "YouTube's player challenges could not be solved: Error: boom.")
        #expect((ChallengeSolverError.malformedOutput as any Error).localizedDescription == "YouTube's player challenge solver returned output Cue could not read.")
        #expect((ChallengeSolverError.solverFailed(kind: .n, message: "Failed to extract n function") as any Error).localizedDescription == "YouTube's n challenge could not be solved: Failed to extract n function.")
        #expect((ChallengeSolverError.solverFailed(kind: .sig, message: "Failed to extract sig function\nError: x\n    at f (core.js:1:1)") as any Error).localizedDescription == "YouTube's sig challenge could not be solved: Failed to extract sig function.")
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

    @Test func fetchesPlayerSourceOnlyOnCacheMiss() async throws {
        let solver = Self.reverseSolver()
        let fetches = Counter()
        for _ in 0..<2 {
            let solved = try await solver.solve(playerID: "p1", challenges: [.n: ["abc"]]) {
                fetches.increment()
                return "player-code"
            }
            #expect(solved[.n] == ["abc": "cba"])
        }
        #expect(fetches.value == 1)
        #expect(solver.hasPreprocessedPlayer("p1"))
        #expect(!solver.hasPreprocessedPlayer("p2"))
    }

    @Test func stopsWhenCancelled() async throws {
        let solver = Self.reverseSolver()
        let fetches = Counter()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await solver.solve(playerID: "p1", challenges: [.n: ["abc"]]) {
                fetches.increment()
                return "player-code"
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fetches.value == 0)
    }

    @Test func queuedColdSolvesReuseTheFirstResult() async throws {
        let solver = Self.reverseSolver()
        let results = try await withThrowingTaskGroup(of: [String: String]?.self) { group in
            for index in 0..<4 {
                group.addTask {
                    try await solver.solve(playerID: "p1", challenges: [.sig: ["s\(index)"]]) { "player-code" }[.sig]
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        let answers = results.compactMap { $0 }.flatMap(\.values)
        #expect(answers.count == 4)
        #expect(answers.filter { $0 == "player" }.count == 1, "only one run should preprocess the player")
    }

    @Test func dedupesConcurrentColdFetchesForTheSamePlayer() async throws {
        let solver = Self.reverseSolver()
        let total = 6
        let fetches = Counter()
        let proceed = AsyncSemaphore()

        // Task group results arrive in completion order, not submission order, so pair each result with the
        // index that produced it rather than assuming `results[index]` corresponds to iteration `index`.
        let results = try await withThrowingTaskGroup(of: (Int, [String: String]?).self) { group in
            for index in 0..<total {
                group.addTask {
                    let solved = try await solver.solve(playerID: "p1", challenges: [.sig: ["s\(index)"]]) {
                        fetches.increment()
                        await proceed.wait()
                        return "player-code"
                    }
                    return (index, solved[.sig])
                }
            }
            // Poll the solver's own join-count bookkeeping rather than a "caller has started running" proxy:
            // an earlier version inferred "every caller has joined" from an in-test counter incremented with no
            // `await` before the call into `solve`, reasoning that Swift never preempts a task mid-synchronous
            // run. That is true for Swift's cooperative scheduling, but says nothing about the OS thread
            // executing that task being descheduled between those two statements — which happens often enough
            // under real CPU contention (many test targets running concurrently) that a straggler could still
            // be short of `fetchTask`'s registration when `allArrived` fired, letting the held-open fetch finish
            // and clear itself before the straggler joined, so it started a second one. `inFlightJoinCountForTesting`
            // is incremented inside the very same lock `fetchTask` uses to register a join, so once it reports
            // `total` here, every caller has provably joined the one in-flight fetch — no timing assumption.
            while solver.inFlightJoinCountForTesting("p1") < total { await Task.yield() }
            proceed.signal()
            var collected: [Int: [String: String]?] = [:]
            for try await (index, result) in group { collected[index] = result }
            return collected
        }
        #expect(fetches.value == 1)
        #expect(results.count == total)
        for index in 0..<total {
            #expect(results[index]??["s\(index)"] != nil)
        }
    }

    @Test func fetchesEachDifferentPlayerIDIndependently() async throws {
        let solver = Self.reverseSolver()
        let fetches = Counter()
        let seenIDs = LockedSet()
        _ = try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<4 {
                group.addTask {
                    let id = "p\(index)"
                    _ = try await solver.solve(playerID: id, challenges: [.sig: ["s"]]) {
                        fetches.increment()
                        seenIDs.insert(id)
                        return "player-code-\(id)"
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(fetches.value == 4)
        #expect(seenIDs.count == 4)
    }

    @Test func failingFetchPropagatesToAllWaitersButAllowsALaterRetry() async throws {
        struct FetchFailed: Error, Equatable {}
        let solver = Self.reverseSolver()
        let total = 4
        let attempts = Counter()
        let proceed = AsyncSemaphore()

        let outcomes = try await withThrowingTaskGroup(of: Result<[String: String]?, Error>.self) { group in
            for index in 0..<total {
                group.addTask {
                    do {
                        let value = try await solver.solve(playerID: "p1", challenges: [.sig: ["s\(index)"]]) {
                            attempts.increment()
                            await proceed.wait()
                            throw FetchFailed()
                        }[.sig]
                        return .success(value)
                    } catch {
                        return .failure(error)
                    }
                }
            }
            // See `dedupesConcurrentColdFetchesForTheSamePlayer` for why polling the solver's own
            // `inFlightJoinCountForTesting` — rather than an in-test "arrived first" counter — is the only
            // provably race-free way to know every caller has joined the one in-flight fetch.
            while solver.inFlightJoinCountForTesting("p1") < total { await Task.yield() }
            proceed.signal()
            var collected: [Result<[String: String]?, Error>] = []
            for try await outcome in group { collected.append(outcome) }
            return collected
        }
        #expect(outcomes.count == total)
        for outcome in outcomes {
            #expect(throws: FetchFailed()) { try outcome.get() }
        }
        #expect(attempts.value == 1, "only one fetch should have been attempted for the failed batch")

        // A later, independent call must be able to retry rather than inherit the failed task.
        let retried = try await solver.solve(playerID: "p1", challenges: [.sig: ["s"]]) {
            attempts.increment()
            return "player-code"
        }
        #expect(retried[.sig]?["s"] != nil)
        #expect(attempts.value == 2)
    }

    @Test func cancellingOneWaiterDoesNotBreakAnotherOnTheSameFetch() async throws {
        let solver = Self.reverseSolver()
        let fetches = Counter()
        let readyToCancel = AsyncSemaphore()
        let survivorStarted = AsyncSemaphore()

        let cancelled = Task {
            try await solver.solve(playerID: "p1", challenges: [.sig: ["cancel-me"]]) {
                fetches.increment()
                await readyToCancel.wait()
                return "player-code"
            }
        }
        // Ensure the shared fetch has actually started before we race the cancellation against it.
        await readyToCancel.waitUntilAwaited()
        cancelled.cancel()

        let survivor = Task {
            // Signalled before `solve` is even called, with no `await` in between: Swift only preempts a task at
            // a suspension point, so by the time the main test observes this signal, `survivor` has already run
            // `solve` synchronously up to its join-or-create decision (the shared fetch is still in flight,
            // since `readyToCancel` has not been signalled yet) — not a timing hope, a happens-before guarantee.
            survivorStarted.signal()
            // `.n` rather than `.sig`: the cancelled caller now also queues a fire-and-forget caching run once
            // its download finishes (see `cancellationAfterADoneDownloadStillQueuesToPopulateTheCache`), which
            // races this caller's own queued run on the same serial queue and may populate the cache first.
            // `reverseCore` answers `.n` challenges from the challenge string alone, so the assertion below does
            // not depend on which of those two queued runs happens to go first.
            return try await solver.solve(playerID: "p1", challenges: [.n: ["survive"]]) {
                fetches.increment()
                await readyToCancel.wait()
                return "player-code"
            }
        }
        await survivorStarted.wait()
        readyToCancel.signal()

        await #expect(throws: CancellationError.self) { try await cancelled.value }
        let survived = try await survivor.value
        #expect(survived[.n] == ["survive": "evivrus"])
        #expect(fetches.value == 1, "the second caller should have joined the first fetch, not started its own")
    }

    @Test func cancellationBeforeTheFetchThrowsWithoutCallingPlayerSource() async throws {
        let solver = Self.reverseSolver()
        let fetches = Counter()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await solver.solve(playerID: "p1", challenges: [.n: ["abc"]]) {
                fetches.increment()
                return "player-code"
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fetches.value == 0)
    }

    @Test func cacheHitMeansNoFetch() async throws {
        let solver = Self.reverseSolver()
        _ = try await solver.solve(playerID: "p1", challenges: [.sig: ["s"]]) { "player-code" }
        #expect(solver.hasPreprocessedPlayer("p1"))

        let fetches = Counter()
        let solved = try await solver.solve(playerID: "p1", challenges: [.sig: ["s"]]) {
            fetches.increment()
            return "should not be called"
        }
        #expect(fetches.value == 0)
        #expect(solved[.sig] == ["s": "preprocessed"])
    }

    @Test func pinnedSnapshotSurvivesEvictionThroughTheAsyncEntryPoint() async throws {
        let solver = Self.reverseSolver()
        _ = try await solver.solve(playerID: "p1", challenges: [.sig: ["s"]]) { "one" }
        let pinned = try #require(solver.cachedPlayer("p1"))
        for id in ["p2", "p3"] {
            _ = try await solver.solve(playerID: id, challenges: [.sig: ["s"]]) { id }
        }
        #expect(!solver.hasPreprocessedPlayer("p1"))

        // The eviction means a fresh async solve would re-download; the throwing overload with the pinned
        // snapshot is what `Extractor` falls back to, and it must still work.
        let solved = try solver.solve(playerID: "p1", playerJS: "", challenges: [.sig: ["s"]], pinnedPreprocessed: pinned)
        #expect(solved[.sig] == ["s": "preprocessed"])
    }

    @Test func cancellationAfterADoneDownloadStillQueuesToPopulateTheCache() async throws {
        // `playerSource` now runs inside the shared fetch's own unstructured task, so cancelling from inside it
        // (as `stopsWhenCancelled` does before the download starts) would cancel the shared fetch, not this
        // caller. To model "this caller was cancelled while its (good) download was in flight", cancel the
        // caller's own `Task` externally once the download has demonstrably started, then let it finish.
        let solver = Self.reverseSolver()
        let started = AsyncSemaphore()
        let proceed = AsyncSemaphore()

        let task = Task {
            try await solver.solve(playerID: "p1", challenges: [.sig: ["s"]]) {
                started.signal()
                await proceed.wait()
                return "player-code"
            }
        }
        await started.wait()
        task.cancel()
        proceed.signal()

        await #expect(throws: CancellationError.self) { try await task.value }
        solver.flushQueueForTesting()
        #expect(solver.hasPreprocessedPlayer("p1"), "the good download should still have been cached even though the caller was cancelled")
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

        // The second solve must reuse the preprocessed player: an empty player source would fail otherwise.
        #expect(solver.cachedPlayer(playerID) != nil)
        let cached = try solver.solve(playerID: playerID, playerJS: "", challenges: [.n: ["0aBcDeFgHiJkLmNoP"]])
        #expect(cached[.n]?["0aBcDeFgHiJkLmNoP"] == output)
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

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private final class LockedSet: @unchecked Sendable {
    private let lock = NSLock()
    private var values: Set<String> = []
    var count: Int { lock.withLock { values.count } }
    func insert(_ value: String) { lock.withLock { _ = values.insert(value) } }
}

/// A single-signal async gate: any number of callers can `wait()`, all resume once `signal()` is called (or
/// immediately if it already was). `waitUntilAwaited()` lets a test block until at least one `wait()` call has
/// actually suspended, so tests can race a cancellation against an in-flight download without sleeping.
private final class AsyncSemaphore: @unchecked Sendable {
    private let lock = NSLock()
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var awaitedContinuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let (resumeNow, notifyAwaited) = lock.withLock { () -> (Bool, CheckedContinuation<Void, Never>?) in
                if isSignaled { return (true, nil) }
                waiters.append(continuation)
                let pending = awaitedContinuation
                awaitedContinuation = nil
                return (false, pending)
            }
            if resumeNow { continuation.resume() }
            notifyAwaited?.resume()
        }
    }

    func waitUntilAwaited() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let readyNow: Bool = lock.withLock {
                if !waiters.isEmpty { return true }
                awaitedContinuation = continuation
                return false
            }
            if readyNow { continuation.resume() }
        }
    }

    func signal() {
        let toResume: [CheckedContinuation<Void, Never>] = lock.withLock {
            isSignaled = true
            let pending = waiters
            waiters.removeAll()
            return pending
        }
        toResume.forEach { $0.resume() }
    }
}
