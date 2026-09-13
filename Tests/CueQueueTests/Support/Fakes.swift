import CueCore
import CuePlayer
@testable import CueQueue
import Foundation

/// Offline HTTP client: answers with the queued responses in order and records every request.
final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    // @unchecked: all mutable state is guarded by `lock`.
    private let lock = NSLock()
    private var responses: [HTTPResponse]
    private var recorded: [URL] = []

    init(_ responses: [HTTPResponse]) {
        self.responses = responses
    }

    var requestedURLs: [URL] { lock.withLock { recorded } }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock {
            recorded.append(request.url)
            return responses.isEmpty ? HTTPResponse(status: 404, body: Data()) : responses.removeFirst()
        }
    }
}

/// Builds the streams a player would report, without resolving anything.
enum FakeStreams {
    static func stream(
        for videoID: VideoID,
        author: String? = nil,
        duration: Double? = 213,
        expiresAt: Date? = nil
    ) -> PlayableStream {
        PlayableStream(
            videoID: videoID,
            title: "Resolved \(videoID.rawValue)",
            author: author,
            videoURL: URL(string: "https://media.example.invalid/\(videoID.rawValue).mp4")!,
            audioURL: URL(string: "https://media.example.invalid/\(videoID.rawValue).m4a")!,
            duration: duration,
            expiresAt: expiresAt
        )
    }
}

/// Stands in for `PlayerController`: records what was opened and reports whatever state a test sets.
@MainActor
final class FakePlayer: QueuePlaying {
    var playerState = PlayerState()
    private(set) var opened: [LaunchInput] = []

    func open(_ input: LaunchInput) async {
        opened.append(input)
    }

    /// The state the player would report while playing a video.
    static func readyState(for videoID: VideoID, author: String? = nil, duration: Double? = 213) -> PlayerState {
        var state = PlayerState()
        state.phase = .ready
        state.stream = FakeStreams.stream(for: videoID, author: author, duration: duration)
        state.duration = duration
        return state
    }

    /// The state the player would report after playback stopped.
    static func endedState(for videoID: VideoID, position: Double, duration: Double?) -> PlayerState {
        var state = PlayerState()
        state.phase = .ended
        state.stream = FakeStreams.stream(for: videoID, duration: duration)
        state.position = position
        state.duration = duration
        return state
    }
}

enum WaitError: Error, CustomStringConvertible {
    case timedOut

    var description: String { "the condition did not hold before the timeout" }
}

/// Sleeps in small steps, letting pending tasks run, until `condition` holds. Throws when it never does, so a test
/// that is quietly waiting for something that cannot happen fails instead of carrying on.
@MainActor
func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { throw WaitError.timedOut }
        try await Task.sleep(for: .milliseconds(5))
    }
}
