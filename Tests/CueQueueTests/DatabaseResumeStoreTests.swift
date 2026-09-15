import CueCore
import CuePlayer
@testable import CueQueue
import Foundation
import Testing

@MainActor
@Suite struct DatabaseResumeStoreTests {
    @Test func savesReadsAndRemovesPositions() throws {
        let store = try TestQueue.store()
        let resumeStore = DatabaseResumeStore(store: store)
        let entry = ResumeEntry(position: 42.5, duration: 213, updatedAt: TestQueue.date)

        resumeStore.save(entry, for: TestQueue.first)
        #expect(resumeStore.entry(for: TestQueue.first) == entry)

        resumeStore.remove(TestQueue.first)
        #expect(resumeStore.entry(for: TestQueue.first) == nil)
    }

    @Test func hasNoEntryForAnUnknownVideo() throws {
        let resumeStore = DatabaseResumeStore(store: try TestQueue.store())
        #expect(resumeStore.entry(for: TestQueue.second) == nil)
    }
}
