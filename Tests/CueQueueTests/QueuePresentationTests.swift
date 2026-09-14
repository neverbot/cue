import CueCore
import CuePlayer
@testable import CueQueue
import Foundation
import Testing

@Suite struct QueuePresentationTests {
    private func videos() throws -> [QueuedVideo] {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, title: "First", author: "Author", duration: 213, addedAt: TestQueue.date)
        try store.add(TestQueue.second, title: "Second", duration: 19, addedAt: TestQueue.date)
        try store.saveResumeEntry(ResumeEntry(position: 106.5, duration: 213, updatedAt: TestQueue.date), for: TestQueue.first)
        return try store.videos()
    }

    @Test func buildsListRowsWithAuthorAndDuration() throws {
        let rows = QueuePresentation.rows(for: try videos(), mode: .list, current: TestQueue.second)

        #expect(rows.count == 2)
        #expect(rows[0].title == "First")
        #expect(rows[0].secondaryText == "Author · 3:33")
        #expect(rows[0].durationText == "3:33")
        #expect(rows[0].isCurrent == false)
        #expect(rows[0].showsThumbnail == false)
        #expect(rows[0].progress == 0.5)
        #expect(rows[1].isCurrent)
        #expect(rows[1].secondaryText == "0:19")
    }

    @Test func leavesTheDurationOutOfCompactRows() throws {
        let rows = QueuePresentation.rows(for: try videos(), mode: .compact)

        #expect(rows[0].secondaryText == "Author")
        #expect(rows[1].secondaryText == "")
        #expect(rows[0].durationText == "3:33")
    }

    @Test func asksForThumbnailsOnlyInThumbnailMode() throws {
        #expect(QueuePresentation.rows(for: try videos(), mode: .thumbnail).allSatisfy(\.showsThumbnail))
        #expect(QueuePresentation.rows(for: try videos(), mode: .list).allSatisfy { !$0.showsThumbnail })
    }

    @Test func showsNoProgressForWatchedVideos() throws {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, title: "First", duration: 213, addedAt: TestQueue.date)
        try store.saveResumeEntry(ResumeEntry(position: 100, duration: 213, updatedAt: TestQueue.date), for: TestQueue.first)
        try store.markWatched(TestQueue.first, at: TestQueue.date)

        let rows = QueuePresentation.rows(for: try store.videos(), mode: .list)
        #expect(rows[0].isWatched)
        #expect(rows[0].progress == nil)
    }

    /// The three cases the row styling turns on: a known title, one not fetched yet, and a real title that happens
    /// to read exactly like a video id.
    @Test func tellsAKnownTitleFromAStandInOne() throws {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, title: "First", addedAt: TestQueue.date)
        try store.add(TestQueue.second, addedAt: TestQueue.date)
        try store.add(TestQueue.third, title: TestQueue.third.rawValue, addedAt: TestQueue.date)

        let rows = QueuePresentation.rows(for: try store.videos(), mode: .list)

        #expect(rows[0].title == "First")
        #expect(rows[0].isTitleKnown)
        // Nothing is known yet, so the row shows the id - and says that it is standing in for a title.
        #expect(rows[1].title == TestQueue.second.rawValue)
        #expect(rows[1].isTitleKnown == false)
        // The same text, but stored as a title: it is the video's name and is drawn as one.
        #expect(rows[2].title == TestQueue.third.rawValue)
        #expect(rows[2].isTitleKnown)
    }

    @Test func countsPendingVideosInTheHeader() {
        #expect(QueuePresentation.counterText(for: QueueSummary()) == "Queue empty")
        #expect(QueuePresentation.counterText(for: QueueSummary(watchedCount: 3)) == "Nothing left to watch")
        #expect(QueuePresentation.counterText(for: QueueSummary(pendingCount: 1)) == "1 video")
        #expect(QueuePresentation.counterText(for: QueueSummary(pendingCount: 12, watchedCount: 4)) == "12 videos")
    }

    @Test func cyclesThroughTheDisplayModes() {
        #expect(QueueDisplayMode.list.next == .thumbnail)
        #expect(QueueDisplayMode.thumbnail.next == .compact)
        #expect(QueueDisplayMode.compact.next == .list)
        #expect(QueueDisplayMode.allCases.map(\.title) == ["List", "Thumbnails", "Compact"])
        #expect(QueueDisplayMode.compact.rowHeight < QueueDisplayMode.list.rowHeight)
        #expect(QueueDisplayMode.list.rowHeight < QueueDisplayMode.thumbnail.rowHeight)
    }

    @Test func namesTheTwoSidebarLayouts() {
        #expect(SidebarLayout.allCases.map(\.rawValue) == ["push", "overlay"])
        #expect(SidebarLayout.push.title == "Push video")
        #expect(SidebarLayout.overlay.title == "Overlay video")
    }
}
