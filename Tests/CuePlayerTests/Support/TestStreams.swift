import CueCore
@testable import CuePlayer
import Foundation

enum TestStreams {
    static let videoID = VideoID("dQw4w9WgXcQ")!
    static let otherVideoID = VideoID("jNQXAC9IVRw")!

    static func stream(for videoID: VideoID = videoID, duration: Double? = 213, expiresAt: Date? = nil) -> PlayableStream {
        PlayableStream(
            videoID: videoID,
            title: "Test stream \(videoID.rawValue)",
            videoURL: URL(string: "https://media.example.invalid/video.mp4")!,
            audioURL: URL(string: "https://media.example.invalid/audio.m4a")!,
            videoSize: VideoSize(width: 1920, height: 1080),
            duration: duration,
            userAgent: "TestBrowser/1.0 (Test, like Gecko)",
            expiresAt: expiresAt
        )
    }
}

@MainActor
final class TestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

/// Sleeps in small steps, letting the main queue and pending tasks run, until `condition` holds or `timeout` passes.
@MainActor
func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(5))
    }
}
