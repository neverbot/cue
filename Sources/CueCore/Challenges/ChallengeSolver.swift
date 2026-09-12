import Foundation
import JavaScriptCore

public enum ChallengeSolverError: Error, Equatable, Sendable {
    case scriptsMissing
    case javaScriptException(String)
    case malformedOutput
    case solverFailed(kind: ChallengeKind, message: String)
}

extension ChallengeSolverError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .scriptsMissing: "Cue's challenge solver scripts are missing."
        case let .javaScriptException(message): "YouTube's player challenges could not be solved: \(message)."
        case .malformedOutput: "YouTube's player challenge solver returned output Cue could not read."
        case let .solverFailed(kind, message):
            "YouTube's \(kind.rawValue) challenge could not be solved: \(message.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? message)."
        }
    }
}

/// Runs yt-dlp's EJS challenge solver (lib + core scripts) inside JavaScriptCore.
/// Caches the preprocessed player per player id, as yt-dlp does, because preprocessing dominates the cost.
public final class ChallengeSolver: @unchecked Sendable {
    static let libFileName = "yt.solver.lib.js"
    static let coreFileName = "yt.solver.core.js"
    /// Player ids rotate over time; older preprocessed players are dropped.
    static let cachedPlayerLimit = 2

    private let libSource: String
    private let coreSource: String
    private let lock = NSLock()
    private var preprocessedPlayers: [(playerID: String, source: String)] = []
    private var inFlightFetches: [String: Task<String, Error>] = [:]
    private let queue = DispatchQueue(label: "cue.challenge-solver")

    public init(libSource: String, coreSource: String) {
        self.libSource = libSource
        self.coreSource = coreSource
    }

    /// Loads `yt.solver.lib.js` and `yt.solver.core.js` from a directory.
    public convenience init(scriptsDirectory: URL) throws {
        guard let libSource = try? String(contentsOf: scriptsDirectory.appendingPathComponent(Self.libFileName), encoding: .utf8),
              let coreSource = try? String(contentsOf: scriptsDirectory.appendingPathComponent(Self.coreFileName), encoding: .utf8)
        else { throw ChallengeSolverError.scriptsMissing }
        self.init(libSource: libSource, coreSource: coreSource)
    }

    /// Loads the scripts shipped with Cue: `Contents/Resources/ejs` inside the app, or the SwiftPM resource bundle
    /// next to a command-line executable (following symlinks to it). Avoids `Bundle.module`, which terminates the
    /// process when its bundle is missing.
    public static func bundled() throws -> ChallengeSolver {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("ejs"),
            Bundle.main.bundleURL.appendingPathComponent("Cue_CueCore.bundle").appendingPathComponent("ejs"),
            Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
                .appendingPathComponent("Cue_CueCore.bundle").appendingPathComponent("ejs"),
        ]
        for case let directory? in candidates {
            if let solver = try? ChallengeSolver(scriptsDirectory: directory) { return solver }
        }
        throw ChallengeSolverError.scriptsMissing
    }

    public func solve(playerID: String, playerJS: String, challenges: [ChallengeKind: [String]]) throws -> [ChallengeKind: [String: String]] {
        try solve(playerID: playerID, playerJS: playerJS, challenges: challenges, pinnedPreprocessed: nil)
    }

    /// `pinnedPreprocessed` is used when the cache no longer holds `playerID` (evicted after the caller checked it).
    func solve(
        playerID: String,
        playerJS: String,
        challenges: [ChallengeKind: [String]],
        pinnedPreprocessed: String?
    ) throws -> [ChallengeKind: [String: String]] {
        let kinds = ChallengeKind.allCases.filter { !(challenges[$0] ?? []).isEmpty }
        guard !kinds.isEmpty else { return [:] }

        var input: [String: Any] = [
            "requests": kinds.map { ["type": $0.rawValue, "challenges": challenges[$0] ?? []] },
        ]
        if let preprocessed = cachedPlayer(playerID) ?? pinnedPreprocessed {
            input["type"] = "preprocessed"
            input["preprocessed_player"] = preprocessed
        } else {
            input["type"] = "player"
            input["player"] = playerJS
            input["output_preprocessed"] = true
        }

        // Runs outside the lock: every run has its own JSContext, and a slow player must not hold up other solves.
        let output = try run(input)
        if let preprocessed = output["preprocessed_player"] as? String {
            cache(preprocessed, for: playerID)
        }
        guard output["type"] as? String == "result",
              let responses = output["responses"] as? [[String: Any]],
              responses.count == kinds.count
        else { throw ChallengeSolverError.malformedOutput }

        var result: [ChallengeKind: [String: String]] = [:]
        for (kind, response) in zip(kinds, responses) {
            guard response["type"] as? String == "result" else {
                throw ChallengeSolverError.solverFailed(kind: kind, message: response["error"] as? String ?? "unknown error")
            }
            guard let data = response["data"] as? [String: String] else { throw ChallengeSolverError.malformedOutput }
            result[kind] = data
        }
        return result
    }

    /// Whether the preprocessed player for `playerID` is cached, so its source need not be downloaded.
    public func hasPreprocessedPlayer(_ playerID: String) -> Bool {
        cachedPlayer(playerID) != nil
    }

    /// Solves challenges one run at a time on a private queue, off the Swift concurrency pool: runs for different
    /// players queue behind each other too, so a cold solve for one player delays others — deliberate, it caps CPU.
    /// Cancellation is honoured before the player download and before queueing; once queued, a run completes and
    /// still populates the cache. `playerSource` is only called when the preprocessed player is not cached, and
    /// concurrent cold callers for the same player id share one in-flight download (see `fetchTask`).
    public func solve(
        playerID: String,
        challenges: [ChallengeKind: [String]],
        playerSource: @escaping @Sendable () async throws -> String
    ) async throws -> [ChallengeKind: [String: String]] {
        try Task.checkCancellation()
        let pinned = cachedPlayer(playerID)
        let playerJS: String
        if pinned == nil {
            playerJS = try await fetchTask(for: playerID, using: playerSource).value
        } else {
            playerJS = ""
        }
        if Task.isCancelled {
            // The download already paid for itself: queue it anyway so the cache still benefits, but do not make
            // this cancelled caller wait for it, and still report the cancellation.
            if pinned == nil, !playerJS.isEmpty {
                queue.async {
                    _ = try? self.solve(playerID: playerID, playerJS: playerJS, challenges: challenges, pinnedPreprocessed: pinned)
                }
            }
            throw CancellationError()
        }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result {
                    try self.solve(playerID: playerID, playerJS: playerJS, challenges: challenges, pinnedPreprocessed: pinned)
                })
            }
        }
    }

    /// Returns the in-flight fetch for `playerID`, joining it if one is already running, or starts one otherwise.
    /// The task is unstructured, so a caller cancelling its own `solve` does not cancel the shared download for
    /// others still waiting on it. Removed from `inFlightFetches` once it finishes, success or failure, so a
    /// failed fetch does not poison later retries.
    private func fetchTask(for playerID: String, using playerSource: @escaping @Sendable () async throws -> String) -> Task<String, Error> {
        lock.withLock {
            if let existing = inFlightFetches[playerID] { return existing }
            let task = Task<String, Error> { [weak self] in
                defer { self?.clearFetch(for: playerID) }
                return try await playerSource()
            }
            inFlightFetches[playerID] = task
            return task
        }
    }

    private func clearFetch(for playerID: String) {
        lock.withLock { _ = inFlightFetches.removeValue(forKey: playerID) }
    }

    /// Blocks until every run enqueued so far on the private solve queue has completed. Test-only synchronisation
    /// point, so assertions after a fire-and-forget caching run do not need to poll or sleep.
    func flushQueueForTesting() {
        queue.sync {}
    }

    func cachedPlayer(_ playerID: String) -> String? {
        lock.withLock { preprocessedPlayers.first { $0.playerID == playerID }?.source }
    }

    private func cache(_ source: String, for playerID: String) {
        lock.withLock {
            preprocessedPlayers.removeAll { $0.playerID == playerID }
            preprocessedPlayers.insert((playerID, source), at: 0)
            if preprocessedPlayers.count > Self.cachedPlayerLimit {
                preprocessedPlayers.removeLast(preprocessedPlayers.count - Self.cachedPlayerLimit)
            }
        }
    }

    private func run(_ input: [String: Any]) throws -> [String: Any] {
        try autoreleasepool {
            guard let context = JSContext() else { throw ChallengeSolverError.javaScriptException("JSContext unavailable") }
            var exception: String?
            context.exceptionHandler = { _, value in
                if exception == nil { exception = value?.toString() }
            }
            context.setObject(input, forKeyedSubscript: "__cueInput" as NSString)

            var json: String?
            for script in [libSource, "Object.assign(globalThis, lib);", coreSource, "JSON.stringify(jsc(__cueInput))"] {
                let value = context.evaluateScript(script)
                if let exception { throw ChallengeSolverError.javaScriptException(exception) }
                json = value?.toString()
            }

            guard let json,
                  let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw ChallengeSolverError.malformedOutput }
            return object
        }
    }
}
