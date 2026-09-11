import Foundation
import JavaScriptCore

public enum ChallengeSolverError: Error, Equatable, Sendable {
    case scriptsMissing
    case javaScriptException(String)
    case malformedOutput
    case solverFailed(kind: String, message: String)
}

extension ChallengeSolverError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .scriptsMissing: "Cue's challenge solver scripts are missing."
        case let .javaScriptException(message): "YouTube's player challenges could not be solved: \(message)."
        case .malformedOutput: "YouTube's player challenge solver returned output Cue could not read."
        case let .solverFailed(kind, message): "YouTube's \(kind) challenge could not be solved: \(message)."
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
    /// next to a command-line executable. Avoids `Bundle.module`, which terminates the process when its bundle is missing.
    public static func bundled() throws -> ChallengeSolver {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("ejs"),
            Bundle.main.bundleURL.appendingPathComponent("Cue_CueCore.bundle").appendingPathComponent("ejs"),
        ]
        for case let directory? in candidates {
            if let solver = try? ChallengeSolver(scriptsDirectory: directory) { return solver }
        }
        throw ChallengeSolverError.scriptsMissing
    }

    public func solve(playerID: String, playerJS: String, challenges: [ChallengeKind: [String]]) throws -> [ChallengeKind: [String: String]] {
        let kinds = ChallengeKind.allCases.filter { !(challenges[$0] ?? []).isEmpty }
        guard !kinds.isEmpty else { return [:] }

        var input: [String: Any] = [
            "requests": kinds.map { ["type": $0.rawValue, "challenges": challenges[$0] ?? []] },
        ]
        if let preprocessed = cachedPlayer(playerID) {
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
                throw ChallengeSolverError.solverFailed(kind: kind.rawValue, message: response["error"] as? String ?? "unknown error")
            }
            guard let data = response["data"] as? [String: String] else { throw ChallengeSolverError.malformedOutput }
            result[kind] = data
        }
        return result
    }

    private func cachedPlayer(_ playerID: String) -> String? {
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
