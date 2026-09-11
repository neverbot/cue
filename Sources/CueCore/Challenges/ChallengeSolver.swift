import Foundation
import JavaScriptCore

public enum ChallengeSolverError: Error, Equatable, Sendable {
    case scriptsMissing
    case javaScriptException(String)
    case malformedOutput
    case solverFailed(kind: String, message: String)
}

/// Runs yt-dlp's EJS challenge solver (lib + core scripts) inside JavaScriptCore.
/// Caches the preprocessed player per player id, as yt-dlp does, because preprocessing dominates the cost.
public final class ChallengeSolver: @unchecked Sendable {
    private let libSource: String
    private let coreSource: String
    private let lock = NSLock()
    private var preprocessedPlayers: [String: String] = [:]

    public init(libSource: String, coreSource: String) {
        self.libSource = libSource
        self.coreSource = coreSource
    }

    public static func bundled() throws -> ChallengeSolver {
        guard let lib = Bundle.module.url(forResource: "yt.solver.lib", withExtension: "js", subdirectory: "ejs"),
              let core = Bundle.module.url(forResource: "yt.solver.core", withExtension: "js", subdirectory: "ejs")
        else { throw ChallengeSolverError.scriptsMissing }
        return ChallengeSolver(
            libSource: try String(contentsOf: lib, encoding: .utf8),
            coreSource: try String(contentsOf: core, encoding: .utf8)
        )
    }

    public func solve(playerID: String, playerJS: String, challenges: [ChallengeKind: [String]]) throws -> [ChallengeKind: [String: String]] {
        try lock.withLock {
            let kinds = ChallengeKind.allCases.filter { !(challenges[$0] ?? []).isEmpty }
            guard !kinds.isEmpty else { return [:] }

            var input: [String: Any] = [
                "requests": kinds.map { ["type": $0.rawValue, "challenges": challenges[$0] ?? []] },
            ]
            if let preprocessed = preprocessedPlayers[playerID] {
                input["type"] = "preprocessed"
                input["preprocessed_player"] = preprocessed
            } else {
                input["type"] = "player"
                input["player"] = playerJS
                input["output_preprocessed"] = true
            }

            let output = try run(input)
            if let preprocessed = output["preprocessed_player"] as? String {
                preprocessedPlayers[playerID] = preprocessed
            }
            guard output["type"] as? String == "result",
                  let responses = output["responses"] as? [[String: Any]],
                  responses.count == kinds.count
            else { throw ChallengeSolverError.malformedOutput }

            var result: [ChallengeKind: [String: String]] = [:]
            for (kind, response) in zip(kinds, responses) {
                guard response["type"] as? String == "result", let data = response["data"] as? [String: String] else {
                    throw ChallengeSolverError.solverFailed(kind: kind.rawValue, message: response["error"] as? String ?? "unknown error")
                }
                result[kind] = data
            }
            return result
        }
    }

    private func run(_ input: [String: Any]) throws -> [String: Any] {
        guard let context = JSContext() else { throw ChallengeSolverError.javaScriptException("JSContext unavailable") }
        var exception: String?
        context.exceptionHandler = { _, value in exception = value?.toString() }

        context.evaluateScript(libSource)
        context.evaluateScript("Object.assign(globalThis, lib);")
        context.evaluateScript(coreSource)
        context.setObject(input, forKeyedSubscript: "__cueInput" as NSString)
        let json = context.evaluateScript("JSON.stringify(jsc(__cueInput))")?.toString()

        if let exception { throw ChallengeSolverError.javaScriptException(exception) }
        guard let json,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ChallengeSolverError.malformedOutput }
        return object
    }
}
