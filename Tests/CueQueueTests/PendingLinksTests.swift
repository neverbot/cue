@testable import CueQueue
import Foundation
import Testing

@Suite struct PendingLinksTests {
    private let first = URL(string: "cue://add?url=dQw4w9WgXcQ")!
    private let second = URL(string: "cue://add?url=jNQXAC9IVRw")!

    @Test func startsEmpty() {
        #expect(PendingLinks().isEmpty)
    }

    @Test func keepsWhatArrivedBeforeTheAppWasReady() {
        var links = PendingLinks()
        links.hold(first)
        links.hold(second)

        #expect(!links.isEmpty)
        // In the order they arrived: two clicks in a row should queue two videos the same way round.
        #expect(links.takeAll() == [first, second])
    }

    @Test func emptiesItselfWhenTaken() {
        var links = PendingLinks()
        links.hold(first)

        _ = links.takeAll()

        // The point of taking and clearing together: a second flush must not add the same video a second time.
        #expect(links.isEmpty)
        #expect(links.takeAll().isEmpty)
    }

    @Test func takingFromAnEmptyStoreIsNothingAtAll() {
        var links = PendingLinks()
        #expect(links.takeAll().isEmpty)
    }
}
