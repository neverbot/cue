@testable import CuePlayer
import Foundation
import Testing

/// Plays the synthetic clip through `MPVPlaybackEngine` without a window. Opt in with `CUE_MPV_TESTS=1`.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CUE_MPV_TESTS"] == "1"))
struct MPVPlaybackEngineTests {
    func clip() throws -> PlayableStream {
        let media = try Media.clip()
        var stream = PlayableStream(fileURL: media.video)
        stream.audioURL = media.audio
        return stream
    }

    @Test func playsTheClipToTheEndAndReportsItsSizeOnce() async throws {
        let engine = try MPVPlaybackEngine(videoOutput: "null", audioOutput: "null")
        var events: [EngineEvent] = []
        engine.onEvent = { events.append($0) }

        engine.load(LoadRequest(stream: try clip(), start: nil))
        try await waitUntil(timeout: .seconds(10)) { events.contains(.ended(.finished)) }

        #expect(events.contains(.fileLoaded))
        #expect(events.contains(.playbackRestarted))
        #expect(events.filter { if case .videoSize = $0 { true } else { false } } == [.videoSize(VideoSize(width: 320, height: 180))])
        #expect(events.contains(.ended(.finished)))
        engine.stop()
        try engine.shutdown()
    }

    @Test func startsAtTheRequestedPosition() async throws {
        let engine = try MPVPlaybackEngine(videoOutput: "null", audioOutput: "null")
        var positions: [Double] = []
        var restarted = false
        engine.onEvent = { event in
            if case let .position(seconds) = event { positions.append(seconds) }
            if event == .playbackRestarted { restarted = true }
        }

        engine.load(LoadRequest(stream: try clip(), start: 2))
        try await waitUntil(timeout: .seconds(10)) { restarted && !positions.isEmpty }

        #expect((positions.first { $0 > 0 } ?? 0) >= 1.9)
        try engine.shutdown()
    }

    @Test func appliesPauseMuteAndVolumeCommands() async throws {
        let engine = try MPVPlaybackEngine(videoOutput: "null", audioOutput: "null")
        var events: [EngineEvent] = []
        engine.onEvent = { events.append($0) }
        engine.load(LoadRequest(stream: try clip(), start: nil))
        try await waitUntil(timeout: .seconds(10)) { events.contains(.playbackRestarted) }

        engine.perform(.togglePause)
        engine.perform(.toggleMute)
        engine.perform(.setVolume(40))
        try await waitUntil(timeout: .seconds(10)) {
            events.contains(.paused(true)) && events.contains(.muted(true)) && events.contains(.volume(40))
        }

        #expect(events.contains(.paused(true)))
        #expect(events.contains(.muted(true)))
        #expect(events.contains(.volume(40)))
        try engine.shutdown()
    }
}
