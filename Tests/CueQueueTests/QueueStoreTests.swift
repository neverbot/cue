import CueCore
import CuePlayer
@testable import CueQueue
import Foundation
import Testing

@Suite struct QueueStoreTests {
    @Test func addsVideosAtTheEndInQueueOrder() throws {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, title: "First", duration: 213, addedAt: TestQueue.date)
        try store.add(TestQueue.second, title: "Second", duration: 19, addedAt: TestQueue.date)

        #expect(try store.videos().map(\.videoID) == [TestQueue.first.rawValue, TestQueue.second.rawValue])
        #expect(try store.videos().first?.title == "First")
        #expect(try store.videos().first?.duration == 213)
    }

    @Test func addsAtTheFront() throws {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, title: "First", addedAt: TestQueue.date)
        try store.add(TestQueue.second, title: "Second", at: .front, addedAt: TestQueue.date)

        #expect(try store.videos().map(\.videoID) == [TestQueue.second.rawValue, TestQueue.first.rawValue])
    }

    @Test func refusesADuplicateWithoutChangingIt() throws {
        let store = try TestQueue.store()
        #expect(try store.add(TestQueue.first, title: "First", addedAt: TestQueue.date))
        #expect(try store.add(TestQueue.first, title: "Again", addedAt: TestQueue.date) == false)

        #expect(try store.videos().count == 1)
        #expect(try store.videos().first?.title == "First")
    }

    /// A video added without a title has none, rather than its own id standing in for one: that is what lets
    /// everything downstream tell a known title from one that is merely not fetched yet.
    @Test func leavesTheTitleUnknownUntilItResolves() throws {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, addedAt: TestQueue.date)

        let video = try #require(try store.video(for: TestQueue.first))
        #expect(video.title == nil)
    }

    /// The perverse case the old placeholder could not survive: a stored title that happens to read exactly like the
    /// video's id is a real title, and a later resolution must not replace it.
    @Test func keepsAStoredTitleThatLooksLikeAVideoID() throws {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, title: TestQueue.first.rawValue, addedAt: TestQueue.date)
        try store.updateMetadata(for: TestQueue.first, title: "Whatever YouTube says today", author: nil, duration: nil)

        #expect(try store.video(for: TestQueue.first)?.title == TestQueue.first.rawValue)
    }

    @Test func fillsInMetadataWithoutMovingTheVideo() throws {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, addedAt: TestQueue.date)
        try store.add(TestQueue.second, addedAt: TestQueue.date)
        try store.updateMetadata(for: TestQueue.first, title: "Resolved", author: "Author", duration: 213)

        let video = try #require(try store.video(for: TestQueue.first))
        #expect(video.title == "Resolved")
        #expect(video.author == "Author")
        #expect(video.duration == 213)
        #expect(try store.videos().map(\.videoID) == [TestQueue.first.rawValue, TestQueue.second.rawValue])
    }

    @Test func keepsTheKnownDurationWhenAResolutionOmitsIt() throws {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, duration: 213, addedAt: TestQueue.date)
        try store.updateMetadata(for: TestQueue.first, title: "Resolved", author: nil, duration: nil)

        let video = try #require(try store.video(for: TestQueue.first))
        #expect(video.duration == 213)
        #expect(video.author == nil)
    }

    /// A title that came from an imported file is the user's, not YouTube's: playing the video must not replace it.
    @Test func keepsATitleThatDidNotComeFromThePlaceholder() throws {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, title: "My own title", addedAt: TestQueue.date)
        try store.updateMetadata(for: TestQueue.first, title: "Whatever YouTube says today", author: "Author", duration: 213)

        let video = try #require(try store.video(for: TestQueue.first))
        #expect(video.title == "My own title")
        #expect(video.author == "Author")
        #expect(video.duration == 213)
    }

    @Test func movesAVideoToAGivenIndex() throws {
        let store = try TestQueue.store()
        for (index, id) in [TestQueue.first, TestQueue.second, TestQueue.third].enumerated() {
            try store.add(id, title: "Video \(index)", addedAt: TestQueue.date)
        }
        try store.move(TestQueue.third, to: 0)

        #expect(try store.videos().map(\.videoID) == [TestQueue.third.rawValue, TestQueue.first.rawValue, TestQueue.second.rawValue])
    }

    @Test func clampsAMoveBeyondTheEnds() throws {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, addedAt: TestQueue.date)
        try store.add(TestQueue.second, addedAt: TestQueue.date)
        try store.move(TestQueue.first, to: 99)

        #expect(try store.videos().map(\.videoID) == [TestQueue.second.rawValue, TestQueue.first.rawValue])
    }

    @Test func removesAVideo() throws {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, addedAt: TestQueue.date)
        try store.remove(TestQueue.first)

        #expect(try store.videos().isEmpty)
        #expect(try store.contains(TestQueue.first) == false)
    }

    /// Removing a video is meant to erase it, not leave a permanent trace of it in the resume table.
    @Test func removingAVideoForgetsWhereItWasWatchedTo() throws {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, duration: 213, addedAt: TestQueue.date)
        try store.saveResumeEntry(ResumeEntry(position: 42, duration: 213, updatedAt: TestQueue.date), for: TestQueue.first)
        try store.remove(TestQueue.first)

        #expect(try store.resumeEntry(for: TestQueue.first) == nil)
    }

    /// The independence of the two tables is deliberate for a video that was never queued: removing an unrelated
    /// video must not touch its resume position.
    @Test func removingAVideoLeavesUnrelatedResumePositionsAlone() throws {
        let store = try TestQueue.store()
        let entry = ResumeEntry(position: 42, duration: 213, updatedAt: TestQueue.date)
        try store.saveResumeEntry(entry, for: TestQueue.second)
        try store.add(TestQueue.first, addedAt: TestQueue.date)
        try store.remove(TestQueue.first)

        #expect(try store.resumeEntry(for: TestQueue.second) == entry)
    }

    @Test func clearingTheQueueForgetsWhereEverythingWasWatchedTo() throws {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, duration: 213, addedAt: TestQueue.date)
        try store.add(TestQueue.second, duration: 19, addedAt: TestQueue.date)
        try store.saveResumeEntry(ResumeEntry(position: 42, duration: 213, updatedAt: TestQueue.date), for: TestQueue.first)
        try store.saveResumeEntry(ResumeEntry(position: 5, duration: 19, updatedAt: TestQueue.date), for: TestQueue.second)
        try store.removeAll()

        #expect(try store.resumeEntry(for: TestQueue.first) == nil)
        #expect(try store.resumeEntry(for: TestQueue.second) == nil)
    }

    /// Clearing the queue must not touch a resume position for a video that was never queued in the first place.
    @Test func clearingTheQueueLeavesUnrelatedResumePositionsAlone() throws {
        let store = try TestQueue.store()
        let entry = ResumeEntry(position: 42, duration: 213, updatedAt: TestQueue.date)
        try store.saveResumeEntry(entry, for: TestQueue.first)
        try store.add(TestQueue.second, addedAt: TestQueue.date)
        try store.removeAll()

        #expect(try store.resumeEntry(for: TestQueue.first) == entry)
    }

    @Test func marksWatchedAndForgetsThePosition() throws {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, duration: 213, addedAt: TestQueue.date)
        try store.saveResumeEntry(ResumeEntry(position: 100, duration: 213, updatedAt: TestQueue.date), for: TestQueue.first)
        try store.markWatched(TestQueue.first, at: TestQueue.date)

        let video = try #require(try store.video(for: TestQueue.first))
        #expect(video.isWatched)
        #expect(video.watchedAt == TestQueue.date)
        #expect(video.resumePosition == nil)
        #expect(try store.resumeEntry(for: TestQueue.first) == nil)
    }

    @Test func marksAWatchedVideoPendingAgain() throws {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, addedAt: TestQueue.date)
        try store.markWatched(TestQueue.first, at: TestQueue.date)
        try store.markUnwatched(TestQueue.first)

        #expect(try store.video(for: TestQueue.first)?.isWatched == false)
    }

    @Test func listsPendingVideosOnly() throws {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, addedAt: TestQueue.date)
        try store.add(TestQueue.second, addedAt: TestQueue.date)
        try store.markWatched(TestQueue.first, at: TestQueue.date)

        #expect(try store.videos(includingWatched: false).map(\.videoID) == [TestQueue.second.rawValue])
        #expect(try store.videos().count == 2)
    }

    @Test func picksTheNextPendingVideoSkippingTheCurrentOne() throws {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, addedAt: TestQueue.date)
        try store.add(TestQueue.second, addedAt: TestQueue.date)
        try store.add(TestQueue.third, addedAt: TestQueue.date)
        try store.markWatched(TestQueue.second, at: TestQueue.date)

        #expect(try store.nextPending()?.videoID == TestQueue.first.rawValue)
        #expect(try store.nextPending(excluding: TestQueue.first)?.videoID == TestQueue.third.rawValue)
    }

    @Test func hasNoNextVideoWhenEverythingIsWatched() throws {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, addedAt: TestQueue.date)
        try store.markWatched(TestQueue.first, at: TestQueue.date)

        #expect(try store.nextPending() == nil)
    }

    @Test func countsPendingAndWatchedVideos() throws {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, duration: 213, addedAt: TestQueue.date)
        try store.add(TestQueue.second, duration: 19, addedAt: TestQueue.date)
        try store.add(TestQueue.third, duration: 100, addedAt: TestQueue.date)
        try store.markWatched(TestQueue.third, at: TestQueue.date)

        let summary = try store.summary()
        #expect(summary.pendingCount == 2)
        #expect(summary.watchedCount == 1)
    }

    /// A position at or past the duration is not a half-watched video, it is a bogus position: the whole video is
    /// still to watch, and the row says so.
    @Test func treatsAResumePositionPastTheDurationAsUnstarted() throws {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, duration: 213, addedAt: TestQueue.date)
        try store.saveResumeEntry(ResumeEntry(position: 500, duration: 213, updatedAt: TestQueue.date), for: TestQueue.first)

        #expect(try store.video(for: TestQueue.first)?.remainingDuration == 213)
    }

    /// A duration of zero (a live stream, a bogus CSV column) is unknown, not "nothing left to watch": the row has no
    /// remaining time to show.
    @Test func treatsAZeroDurationAsUnknown() throws {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, duration: 0, addedAt: TestQueue.date)

        #expect(try store.video(for: TestQueue.first)?.remainingDuration == nil)
    }

    @Test func summarisesAnEmptyQueue() throws {
        #expect(try TestQueue.store().summary() == QueueSummary())
    }

    @Test func keepsResumePositionsForVideosThatAreNotQueued() throws {
        let store = try TestQueue.store()
        let entry = ResumeEntry(position: 42, duration: 213, updatedAt: TestQueue.date)
        try store.saveResumeEntry(entry, for: TestQueue.first)

        #expect(try store.resumeEntry(for: TestQueue.first) == entry)
        #expect(try store.videos().isEmpty)
    }

    @Test func replacesAndRemovesResumePositions() throws {
        let store = try TestQueue.store()
        try store.saveResumeEntry(ResumeEntry(position: 42, duration: 213, updatedAt: TestQueue.date), for: TestQueue.first)
        try store.saveResumeEntry(ResumeEntry(position: 90, duration: 213, updatedAt: TestQueue.date), for: TestQueue.first)
        #expect(try store.resumeEntry(for: TestQueue.first)?.position == 90)

        try store.removeResumeEntry(for: TestQueue.first)
        #expect(try store.resumeEntry(for: TestQueue.first) == nil)
    }

    @Test func pinsTheRegisteredMigrations() {
        #expect(QueueDatabase.migrationNames == ["v1-queue"])
    }

    @Test func keepsTheQueueBetweenOpensOfTheSameFile() throws {
        let directory = TestQueue.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "Cue/queue.sqlite")

        let first = QueueStore(database: try QueueDatabase.open(at: fileURL))
        try first.add(TestQueue.first, title: "Kept", duration: 213, addedAt: TestQueue.date)

        let second = QueueStore(database: try QueueDatabase.open(at: fileURL))
        #expect(try second.videos().map(\.title) == ["Kept"])
    }
}
