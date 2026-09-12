import CueCore
@testable import CuePlayer
import Foundation
import Testing

@MainActor
@Suite struct PlayerControllerTests {
    let engine = FakeEngine()
    let store = InMemoryResumeStore()
    let clock = TestClock()

    func makeController(_ resolver: FakeResolver) -> PlayerController {
        PlayerController(engine: engine, resolver: resolver, resumeStore: store, saveInterval: 5, now: { [clock] in clock.now })
    }

    func play(_ controller: PlayerController, at position: Double) {
        engine.emit(.fileLoaded, .playbackRestarted, .paused(false), .position(position))
    }

    @Test func opensAVideoAtItsResumePosition() async {
        store.entries[TestStreams.videoID] = ResumeEntry(position: 42, duration: 213, updatedAt: clock.now)
        let controller = makeController(FakeResolver([.success(TestStreams.stream())]))

        await controller.open(.video(TestStreams.videoID))

        #expect(engine.loaded == [LoadRequest(stream: TestStreams.stream(), start: 42)])
        #expect(engine.pausedCalls == [false])
        #expect(controller.state.phase == .loading)
        #expect(controller.state.videoSize == VideoSize(width: 1920, height: 1080))
    }

    @Test func startsFromTheBeginningWhenTheSavedPositionIsNearTheEnd() async {
        store.entries[TestStreams.videoID] = ResumeEntry(position: 200, duration: 213, updatedAt: clock.now)
        let controller = makeController(FakeResolver([.success(TestStreams.stream())]))

        await controller.open(.video(TestStreams.videoID))

        #expect(engine.loaded.first?.start == nil)
    }

    @Test func reportsResolutionFailures() async {
        let controller = makeController(FakeResolver([.failure(ExtractionError.noPlayableFormats)]))

        await controller.open(.video(TestStreams.videoID))

        #expect(controller.state.phase == .failed(ExtractionError.noPlayableFormats.errorDescription!))
        #expect(engine.loaded.isEmpty)
    }

    @Test func savesThePositionPeriodicallyAndOnPause() async {
        let controller = makeController(FakeResolver([.success(TestStreams.stream())]))
        await controller.open(.video(TestStreams.videoID))
        play(controller, at: 20)
        #expect(store.entries[TestStreams.videoID] == nil)

        clock.advance(by: 6)
        engine.emit(.position(30))
        #expect(store.entries[TestStreams.videoID]?.position == 30)

        engine.emit(.position(31))
        #expect(store.entries[TestStreams.videoID]?.position == 30)

        engine.emit(.paused(true))
        #expect(store.entries[TestStreams.videoID]?.position == 31)
    }

    @Test func forgetsFinishedVideos() async {
        store.entries[TestStreams.videoID] = ResumeEntry(position: 42, duration: 213, updatedAt: clock.now)
        let controller = makeController(FakeResolver([.success(TestStreams.stream())]))
        await controller.open(.video(TestStreams.videoID))
        play(controller, at: 212)

        engine.emit(.ended(.finished))

        #expect(store.entries[TestStreams.videoID] == nil)
        #expect(controller.state.phase == .ended)
    }

    @Test func keepsThePositionWhenPlaybackEndsWithAnUnknownDuration() async throws {
        let resolver = FakeResolver([
            TestStreams.stream(duration: nil, expiresAt: clock.now.addingTimeInterval(3600)),
            TestStreams.stream(duration: nil, expiresAt: clock.now.addingTimeInterval(7200)),
        ].map(Result.success))
        let controller = makeController(resolver)
        await controller.open(.video(TestStreams.videoID))
        play(controller, at: 100)
        clock.advance(by: 3600)

        engine.emit(.ended(.finished))
        try await waitUntil { engine.loaded.count == 2 }

        #expect(store.entries[TestStreams.videoID]?.position == 100)
        #expect(engine.loaded.last?.start == 100)
    }

    @Test func keepsThePositionWhenPlaybackEndsEarly() async {
        let controller = makeController(FakeResolver([.success(TestStreams.stream(expiresAt: clock.now.addingTimeInterval(3600)))]))
        await controller.open(.video(TestStreams.videoID))
        play(controller, at: 100)

        engine.emit(.ended(.finished))

        #expect(store.entries[TestStreams.videoID]?.position == 100)
        #expect(engine.loaded.count == 1)
    }

    @Test func reResolvesWhenAnExpiredStreamEndsEarly() async throws {
        let resolver = FakeResolver([
            .success(TestStreams.stream(expiresAt: clock.now.addingTimeInterval(3600))),
            .success(TestStreams.stream(expiresAt: clock.now.addingTimeInterval(7200))),
        ])
        let controller = makeController(resolver)
        await controller.open(.video(TestStreams.videoID))
        play(controller, at: 100)
        clock.advance(by: 3600)

        engine.emit(.ended(.finished))
        try await waitUntil { engine.loaded.count == 2 }

        #expect(store.entries[TestStreams.videoID]?.position == 100)
        #expect(engine.loaded.last?.start == 100)
    }

    @Test func reResolvesExpiredStreamsBeforeSeeking() async throws {
        let resolver = FakeResolver([
            .success(TestStreams.stream(expiresAt: clock.now.addingTimeInterval(3600))),
            .success(TestStreams.stream(expiresAt: clock.now.addingTimeInterval(7200))),
        ])
        let controller = makeController(resolver)
        await controller.open(.video(TestStreams.videoID))
        play(controller, at: 100)
        clock.advance(by: 3600)

        controller.perform(.seekAbsolute(seconds: 150))
        try await waitUntil { engine.loaded.count == 2 }

        #expect(engine.commands.isEmpty)
        #expect(engine.loaded.last?.start == 150)
        #expect(resolver.requests.count == 2)
    }

    @Test func ignoresCommandsWhileResolving() async {
        let controller = makeController(FakeResolver([.success(TestStreams.stream())], delays: [TestStreams.videoID: .milliseconds(50)]))
        let opening = Task { await controller.open(.video(TestStreams.videoID)) }

        controller.perform(.togglePause)
        controller.perform(.seekRelative(seconds: 5))
        await opening.value

        #expect(engine.commands.isEmpty)
    }

    @Test func keepsTheSavedPositionWhenClosedBeforePlaybackStarts() async {
        let saved = ResumeEntry(position: 42, duration: 213, updatedAt: clock.now)
        store.entries[TestStreams.videoID] = saved
        let controller = makeController(FakeResolver([.success(TestStreams.stream())]))
        await controller.open(.video(TestStreams.videoID))

        controller.close()

        #expect(store.entries[TestStreams.videoID] == saved)
        #expect(engine.stopCount == 1)
        #expect(controller.state.phase == .idle)
    }

    @Test func savesThePositionOnClose() async {
        let controller = makeController(FakeResolver([.success(TestStreams.stream())]))
        await controller.open(.video(TestStreams.videoID))
        play(controller, at: 55)

        controller.close()

        #expect(store.entries[TestStreams.videoID]?.position == 55)
        #expect(engine.stopCount == 1)
    }

    @Test func savesThePreviousVideosPositionWhenOpeningTheNextOne() async {
        let controller = makeController(FakeResolver(
            [.success(TestStreams.stream()), .success(TestStreams.stream(for: TestStreams.otherVideoID))]
        ))
        await controller.open(.video(TestStreams.videoID))
        play(controller, at: 77)

        await controller.open(.video(TestStreams.otherVideoID))

        #expect(store.entries[TestStreams.videoID]?.position == 77)
    }

    @Test func togglesPauseDirectlyWhileStreamsAreFresh() async {
        let controller = makeController(FakeResolver([.success(TestStreams.stream(expiresAt: clock.now.addingTimeInterval(3600)))]))
        await controller.open(.video(TestStreams.videoID))
        play(controller, at: 20)
        engine.emit(.paused(true))

        controller.perform(.togglePause)

        #expect(engine.commands == [.togglePause])
        #expect(engine.loaded.count == 1)
    }

    @Test func reResolvesExpiredStreamsBeforeResuming() async throws {
        let resolver = FakeResolver([
            .success(TestStreams.stream(expiresAt: clock.now.addingTimeInterval(3600))),
            .success(TestStreams.stream(expiresAt: clock.now.addingTimeInterval(7200))),
        ])
        let controller = makeController(resolver)
        await controller.open(.video(TestStreams.videoID))
        play(controller, at: 100)
        engine.emit(.paused(true))
        clock.advance(by: 3600)

        controller.perform(.togglePause)
        try await waitUntil { engine.loaded.count == 2 }

        #expect(engine.commands.isEmpty)
        #expect(resolver.requests == [TestStreams.videoID, TestStreams.videoID])
        #expect(engine.loaded.last?.start == 100)
        #expect(engine.pausedCalls == [false, false])
    }

    @Test func reResolvesOnceWhenAnExpiredStreamFails() async throws {
        let resolver = FakeResolver([
            .success(TestStreams.stream(expiresAt: clock.now.addingTimeInterval(3600))),
            .success(TestStreams.stream(expiresAt: clock.now.addingTimeInterval(7200))),
        ])
        let controller = makeController(resolver)
        await controller.open(.video(TestStreams.videoID))
        play(controller, at: 100)
        clock.advance(by: 7200)

        engine.emit(.ended(.failed("loading failed")))
        try await waitUntil { engine.loaded.count == 2 }
        engine.emit(.ended(.failed("loading failed")))
        try await Task.sleep(for: .milliseconds(50))

        #expect(engine.loaded.count == 2)
        #expect(controller.state.phase == .failed("loading failed"))
    }

    @Test func ignoresAResolutionTheUserMovedPast() async throws {
        let resolver = FakeResolver(
            [.success(TestStreams.stream(for: TestStreams.otherVideoID)), .success(TestStreams.stream())],
            delays: [TestStreams.videoID: .milliseconds(200)]
        )
        let controller = makeController(resolver)

        let slow = Task { await controller.open(.video(TestStreams.videoID)) }
        try await waitUntil { resolver.requests.count == 1 }
        await controller.open(.video(TestStreams.otherVideoID))
        await slow.value

        #expect(engine.loaded.map(\.stream.videoID) == [TestStreams.otherVideoID])
        #expect(controller.state.stream?.videoID == TestStreams.otherVideoID)
    }

    @Test func seeksReachTheEngineWhenTheStreamIsFresh() async {
        let controller = makeController(FakeResolver([.success(TestStreams.stream(expiresAt: clock.now.addingTimeInterval(3600)))]))
        await controller.open(.video(TestStreams.videoID))
        play(controller, at: 20)

        controller.perform(.seekAbsolute(seconds: 30))

        #expect(engine.commands == [.seekAbsolute(seconds: 30)])
        #expect(engine.loaded.count == 1)
    }

    @Test func clampsARelativeSeekBelowZeroWhenReResolving() async throws {
        let resolver = FakeResolver([
            TestStreams.stream(expiresAt: clock.now.addingTimeInterval(3600)),
            TestStreams.stream(expiresAt: clock.now.addingTimeInterval(7200)),
        ].map(Result.success))
        let controller = makeController(resolver)
        await controller.open(.video(TestStreams.videoID))
        play(controller, at: 10)
        clock.advance(by: 3600)

        controller.perform(.seekRelative(seconds: -1000))
        try await waitUntil { engine.loaded.count == 2 }

        #expect(engine.loaded.last?.start == 0)
    }

    @Test func preservesThePauseAcrossASeekOnAnExpiredStream() async throws {
        let resolver = FakeResolver([
            .success(TestStreams.stream(expiresAt: clock.now.addingTimeInterval(3600))),
            .success(TestStreams.stream(expiresAt: clock.now.addingTimeInterval(7200))),
        ])
        let controller = makeController(resolver)
        await controller.open(.video(TestStreams.videoID))
        play(controller, at: 100)
        engine.emit(.paused(true))
        clock.advance(by: 3600)

        controller.perform(.seekAbsolute(seconds: 150))
        try await waitUntil { engine.loaded.count == 2 }

        #expect(engine.loaded.last?.start == 150)
        #expect(engine.pausedCalls == [false, true])
    }

    @Test func allowsVolumeAndMuteWithNoStream() async {
        let controller = makeController(FakeResolver([]))

        controller.perform(.setVolume(40))
        controller.perform(.toggleMute)
        controller.perform(.seekAbsolute(seconds: 5))

        #expect(engine.commands == [.setVolume(40), .toggleMute])
    }

    @Test func opensLocalFilesWithoutResolving() async {
        let resolver = FakeResolver([])
        let controller = makeController(resolver)

        await controller.open(.file(URL(fileURLWithPath: "/tmp/test clip.mp4")))

        #expect(resolver.requests.isEmpty)
        #expect(engine.loaded.first?.arguments == ["loadfile", "/tmp/test clip.mp4", "replace"])
    }
}
