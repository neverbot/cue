import CueCore
@testable import CuePlayer
import Foundation

@MainActor
final class FakeEngine: PlaybackEngine {
    var onEvent: ((EngineEvent) -> Void)?
    private(set) var loaded: [LoadRequest] = []
    private(set) var pausedCalls: [Bool] = []
    private(set) var commands: [PlayerCommand] = []
    private(set) var stopCount = 0

    func load(_ request: LoadRequest) { loaded.append(request) }
    func setPaused(_ paused: Bool) { pausedCalls.append(paused) }
    func perform(_ command: PlayerCommand) { commands.append(command) }
    func stop() { stopCount += 1 }

    func emit(_ events: EngineEvent...) {
        for event in events { onEvent?(event) }
    }
}

/// Answers each request with the first queued result for that video (a failure answers any video); an optional
/// per-video delay lets tests overlap two opens.
final class FakeResolver: StreamResolving, @unchecked Sendable {
    // @unchecked: all mutable state is guarded by `lock`.
    private let lock = NSLock()
    private var results: [Result<PlayableStream, any Error>]
    private var delays: [VideoID: Duration]
    private var requested: [VideoID] = []

    init(_ results: [Result<PlayableStream, any Error>], delays: [VideoID: Duration] = [:]) {
        self.results = results
        self.delays = delays
    }

    var requests: [VideoID] { lock.withLock { requested } }

    func stream(for videoID: VideoID) async throws -> PlayableStream {
        let delay = lock.withLock { () -> Duration? in
            requested.append(videoID)
            return delays[videoID]
        }
        if let delay { try await Task.sleep(for: delay) }
        let result = lock.withLock { () -> Result<PlayableStream, any Error> in
            let index = results.firstIndex { result in
                guard case let .success(stream) = result else { return true }
                return stream.videoID == videoID
            }
            guard let index else { return .failure(ExtractionError.noPlayableFormats) }
            return results.remove(at: index)
        }
        return try result.get()
    }
}

@MainActor
final class InMemoryResumeStore: ResumeStore {
    var entries: [VideoID: ResumeEntry] = [:]

    func entry(for videoID: VideoID) -> ResumeEntry? { entries[videoID] }
    func save(_ entry: ResumeEntry, for videoID: VideoID) { entries[videoID] = entry }
    func remove(_ videoID: VideoID) { entries[videoID] = nil }
}
