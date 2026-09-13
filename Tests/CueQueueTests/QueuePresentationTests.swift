import CueCore
import CuePlayer
@testable import CueQueue
import Foundation
import Testing

@Suite struct PendingTimeTests {
    @Test func formatsTheUnitsAQueueIsJudgedBy() {
        #expect(PendingTime.format(0) == "0 min")
        #expect(PendingTime.format(59) == "0 min")
        #expect(PendingTime.format(219) == "3 min")
        #expect(PendingTime.format(2880) == "48 min")
        #expect(PendingTime.format(12_060) == "3 h 21 min")
        #expect(PendingTime.format(187_200) == "2 d 4 h")
    }

    @Test func readsNegativeAndNonFiniteValuesAsNothingPending() {
        #expect(PendingTime.format(-10) == "0 min")
        #expect(PendingTime.format(.infinity) == "0 min")
        #expect(PendingTime.format(.nan) == "0 min")
    }
}

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

    @Test func countsVideosAndPendingTimeInTheHeader() {
        #expect(QueuePresentation.counterText(for: QueueSummary()) == "Queue empty")
        #expect(QueuePresentation.counterText(for: QueueSummary(watchedCount: 3)) == "Nothing left to watch")
        #expect(QueuePresentation.counterText(for: QueueSummary(pendingCount: 1, pendingDuration: 213)) == "1 video · 3 min")
        #expect(QueuePresentation.counterText(for: QueueSummary(pendingCount: 12, pendingDuration: 12_060)) == "12 videos · 3 h 21 min")
    }

    @Test func marksThePendingTimeAsAFloorWhenADurationIsMissing() {
        let summary = QueueSummary(pendingCount: 3, pendingDuration: 12_060, unknownDurationCount: 1)
        #expect(QueuePresentation.counterText(for: summary) == "3 videos · 3 h 21 min+")
    }

    @Test func saysTheTimeIsUnknownWhenNoDurationIsKnownAtAll() {
        let summary = QueueSummary(pendingCount: 2, pendingDuration: 0, unknownDurationCount: 2)
        #expect(QueuePresentation.counterText(for: summary) == "2 videos · time unknown")
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
