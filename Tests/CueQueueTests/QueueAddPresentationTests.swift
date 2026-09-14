import CueCore
@testable import CueQueue
import Foundation
import Testing

@Suite struct QueueAddPresentationTests {
    @Test func reportsAVideoThatWasAdded() {
        let outcome = QueueAddPresentation.outcome(videoID: TestQueue.first, wasAdded: true)

        #expect(outcome == .added)
        #expect(QueueAddPresentation.message(for: outcome) == "Added to the queue.")
    }

    @Test func reportsAVideoTheQueueAlreadyHad() {
        let outcome = QueueAddPresentation.outcome(videoID: TestQueue.first, wasAdded: false)

        #expect(outcome == .alreadyQueued)
        #expect(QueueAddPresentation.message(for: outcome) == "That video is already in the queue.")
    }

    @Test func reportsTextThatNamesNoVideo() {
        let outcome = QueueAddPresentation.outcome(videoID: nil, wasAdded: false)

        #expect(outcome == .notRecognised)
        #expect(QueueAddPresentation.message(for: outcome) == "That is not a YouTube video id or link.")
    }

    /// Nothing the owner typed is quoted back: these lines go on screen beside their own queue.
    @Test func repeatsNothingThatWasTyped() {
        for outcome in [QueueAddOutcome.added, .alreadyQueued, .notRecognised] {
            let message = QueueAddPresentation.message(for: outcome)
            #expect(!message.contains(TestQueue.first.rawValue))
            #expect(!message.contains("\""))
        }
    }

    /// The outcome follows what the store reported, which is exactly what makes a second paste of the same link say
    /// so instead of silently doing nothing.
    @Test func followsWhatTheQueueReportedForARealStore() throws {
        let store = try TestQueue.store()

        let first = QueueAddPresentation.outcome(
            videoID: TestQueue.first, wasAdded: try store.add(TestQueue.first, addedAt: TestQueue.date)
        )
        let second = QueueAddPresentation.outcome(
            videoID: TestQueue.first, wasAdded: try store.add(TestQueue.first, addedAt: TestQueue.date)
        )

        #expect(first == .added)
        #expect(second == .alreadyQueued)
    }
}
