import CueCore
import CuePlayer
@testable import CueQueue
import Foundation
import Testing

@MainActor
@Suite struct QueueCoordinatorTests {
    private func queue(_ ids: [VideoID] = [TestQueue.first, TestQueue.second, TestQueue.third]) throws -> QueueStore {
        let store = try TestQueue.store()
        for id in ids {
            try store.add(id, duration: 213, addedAt: TestQueue.date)
        }
        return store
    }

    @Test func playsTheFirstPendingVideo() async throws {
        let store = try queue()
        let player = FakePlayer()
        let coordinator = QueueCoordinator(store: store, player: player, now: { TestQueue.date })

        #expect(coordinator.playNext())
        try await waitUntil { !player.opened.isEmpty }

        #expect(player.opened == [.video(TestQueue.first)])
        #expect(coordinator.currentVideoID == TestQueue.first)
    }

    @Test func skipsWatchedVideosAndTheOnePlaying() async throws {
        let store = try queue()
        try store.markWatched(TestQueue.second, at: TestQueue.date)
        let player = FakePlayer()
        let coordinator = QueueCoordinator(store: store, player: player, now: { TestQueue.date })

        coordinator.play(TestQueue.first)
        #expect(coordinator.playNext())
        try await waitUntil { player.opened.count == 2 }

        #expect(player.opened == [.video(TestQueue.first), .video(TestQueue.third)])
    }

    @Test func reportsWhenNothingIsLeftToPlay() throws {
        let store = try queue([TestQueue.first])
        try store.markWatched(TestQueue.first, at: TestQueue.date)
        let coordinator = QueueCoordinator(store: store, player: FakePlayer(), now: { TestQueue.date })

        #expect(coordinator.playNext() == false)
        #expect(coordinator.currentVideoID == nil)
    }

    @Test func addsAndPlaysAVideoAtTheFrontOfTheQueue() async throws {
        let store = try queue([TestQueue.second])
        let player = FakePlayer()
        let coordinator = QueueCoordinator(store: store, player: player, now: { TestQueue.date })

        coordinator.addAndPlay(TestQueue.first)
        try await waitUntil { !player.opened.isEmpty }

        #expect(try store.videos().map(\.videoID) == [TestQueue.first.rawValue, TestQueue.second.rawValue])
        #expect(player.opened == [.video(TestQueue.first)])
    }

    @Test func marksAVideoWatchedWhenItReachesTheEndAndPlaysTheNextOne() async throws {
        let store = try queue()
        let player = FakePlayer()
        let coordinator = QueueCoordinator(store: store, player: player, now: { TestQueue.date })
        coordinator.play(TestQueue.first)
        try await waitUntil { !player.opened.isEmpty }

        coordinator.playerStateChanged(FakePlayer.endedState(for: TestQueue.first, position: 200, duration: 213))
        try await waitUntil { player.opened.count == 2 }

        #expect(try store.video(for: TestQueue.first)?.isWatched == true)
        #expect(player.opened == [.video(TestQueue.first), .video(TestQueue.second)])
        #expect(coordinator.currentVideoID == TestQueue.second)
    }

    @Test func keepsAVideoPendingWhenPlaybackStopsEarly() throws {
        let store = try queue()
        let coordinator = QueueCoordinator(store: store, player: FakePlayer(), now: { TestQueue.date })
        coordinator.play(TestQueue.first)

        coordinator.playerStateChanged(FakePlayer.endedState(for: TestQueue.first, position: 42, duration: 213))

        #expect(try store.video(for: TestQueue.first)?.isWatched == false)
        #expect(coordinator.currentVideoID == TestQueue.first)
    }

    @Test func keepsAVideoPendingWhenTheDurationIsUnknown() throws {
        let store = try queue()
        let coordinator = QueueCoordinator(store: store, player: FakePlayer(), now: { TestQueue.date })
        coordinator.play(TestQueue.first)

        coordinator.playerStateChanged(FakePlayer.endedState(for: TestQueue.first, position: 5000, duration: nil))

        #expect(try store.video(for: TestQueue.first)?.isWatched == false)
    }

    /// A dying stream reports `.ended` too. The player re-resolves and plays on, so the genuine finish that follows
    /// must still be acted on.
    @Test func marksTheVideoWatchedWhenItFinishesAfterAnEarlyEnd() async throws {
        let store = try queue()
        let player = FakePlayer()
        let coordinator = QueueCoordinator(store: store, player: player, now: { TestQueue.date })
        coordinator.play(TestQueue.first)
        try await waitUntil { !player.opened.isEmpty }

        coordinator.playerStateChanged(FakePlayer.endedState(for: TestQueue.first, position: 42, duration: 213))
        #expect(try store.video(for: TestQueue.first)?.isWatched == false)

        coordinator.playerStateChanged(FakePlayer.endedState(for: TestQueue.first, position: 205, duration: 213))

        #expect(try store.video(for: TestQueue.first)?.isWatched == true)
    }

    @Test func handlesTheEndOfAVideoOnlyOnce() async throws {
        let store = try queue()
        let player = FakePlayer()
        let coordinator = QueueCoordinator(store: store, player: player, now: { TestQueue.date })
        coordinator.play(TestQueue.first)
        try await waitUntil { !player.opened.isEmpty }

        let ended = FakePlayer.endedState(for: TestQueue.first, position: 200, duration: 213)
        coordinator.playerStateChanged(ended)
        try await waitUntil { player.opened.count == 2 }
        coordinator.playerStateChanged(ended)
        coordinator.playerStateChanged(ended)

        #expect(player.opened == [.video(TestQueue.first), .video(TestQueue.second)])
    }

    @Test func stopsAtTheEndOfTheQueueWhenTheLastVideoFinishes() async throws {
        let store = try queue([TestQueue.first])
        let player = FakePlayer()
        let coordinator = QueueCoordinator(store: store, player: player, now: { TestQueue.date })
        coordinator.play(TestQueue.first)
        try await waitUntil { !player.opened.isEmpty }

        coordinator.playerStateChanged(FakePlayer.endedState(for: TestQueue.first, position: 213, duration: 213))

        #expect(try store.video(for: TestQueue.first)?.isWatched == true)
        #expect(coordinator.currentVideoID == nil)
        #expect(player.opened.count == 1)
    }

    @Test func leavesTheNextVideoAloneWhenAutomaticPlaybackIsOff() async throws {
        let store = try queue()
        let player = FakePlayer()
        let coordinator = QueueCoordinator(store: store, player: player, now: { TestQueue.date })
        coordinator.playsNextAutomatically = false
        coordinator.play(TestQueue.first)
        try await waitUntil { !player.opened.isEmpty }

        coordinator.playerStateChanged(FakePlayer.endedState(for: TestQueue.first, position: 213, duration: 213))

        #expect(try store.video(for: TestQueue.first)?.isWatched == true)
        #expect(player.opened.count == 1)
        #expect(coordinator.currentVideoID == nil)
    }

    @Test func marksTheCurrentVideoWatchedOnRequest() throws {
        let store = try queue()
        let coordinator = QueueCoordinator(store: store, player: FakePlayer(), now: { TestQueue.date })
        coordinator.play(TestQueue.first)

        coordinator.markCurrentWatched()

        #expect(try store.video(for: TestQueue.first)?.watchedAt == TestQueue.date)
    }

    @Test func fillsInWhatTheExtractorLearnedAboutTheVideo() throws {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, addedAt: TestQueue.date)
        let coordinator = QueueCoordinator(store: store, player: FakePlayer(), now: { TestQueue.date })
        coordinator.play(TestQueue.first)

        coordinator.playerStateChanged(FakePlayer.readyState(for: TestQueue.first, author: "Author", duration: 213))

        let video = try #require(try store.video(for: TestQueue.first))
        #expect(video.title == "Resolved dQw4w9WgXcQ")
        #expect(video.author == "Author")
        #expect(video.duration == 213)
    }

    @Test func reportsEveryChangeTheSidebarShouldRedrawFor() throws {
        let store = try queue()
        let coordinator = QueueCoordinator(store: store, player: FakePlayer(), now: { TestQueue.date })
        var changes = 0
        coordinator.onQueueChange = { changes += 1 }

        coordinator.play(TestQueue.first)
        coordinator.markCurrentWatched()

        #expect(changes == 2)
    }
}
