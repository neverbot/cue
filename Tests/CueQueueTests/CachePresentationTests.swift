@testable import CueQueue
import Foundation
import Testing

/// The formatted byte counts are checked for shape rather than for an exact string: `ByteCountFormatter` is localised,
/// and pinning "12.4 MB" would make these tests fail on a machine whose decimal separator is a comma. What is asserted
/// exactly is what this code actually decides — when a count is reported in words instead of digits, and how the
/// sentences around the number are built.
@Suite struct CachePresentationTests {
    @Test func saysAnEmptyCacheIsEmptyRatherThanShowingAZero() {
        #expect(CachePresentation.sizeText(bytes: 0) == "Empty")
        // A negative total can only come from a bad measurement; it is still nothing on disk.
        #expect(CachePresentation.sizeText(bytes: -1) == "Empty")
    }

    @Test func formatsASizeItActuallyHas() {
        let text = CachePresentation.sizeText(bytes: 12_400_000)

        let hasDigits = text.contains(where: \.isNumber)
        #expect(text != "Empty")
        #expect(text.contains("MB"))
        #expect(hasDigits)
    }

    @Test func reportsWhatEmptyingFreed() {
        let text = CachePresentation.freedText(bytes: 12_400_000)

        #expect(text.hasPrefix("Freed "))
        #expect(text.hasSuffix("."))
        #expect(text.contains("MB"))
    }

    @Test func admitsWhenThereWasNothingToFree() {
        #expect(CachePresentation.freedText(bytes: 0) == "The cache was already empty.")
    }

    @Test func countsProgressThroughTheQueue() {
        #expect(CachePresentation.progressText(completed: 34, total: 210) == "34 of 210")
        #expect(CachePresentation.progressText(completed: 0, total: 1) == "0 of 1")
        #expect(CachePresentation.progressText(completed: -3, total: -3) == "0 of 0")
    }

    @Test func reportsAFinishedRefetch() {
        #expect(CachePresentation.refetchedText(completed: 210, total: 210, cancelled: false) == "Fetched 210 thumbnails.")
        #expect(CachePresentation.refetchedText(completed: 1, total: 1, cancelled: false) == "Fetched 1 thumbnail.")
        #expect(CachePresentation.refetchedText(completed: 0, total: 0, cancelled: false) == "Fetched 0 thumbnails.")
    }

    @Test func saysHowFarACancelledRefetchGot() {
        #expect(CachePresentation.refetchedText(completed: 34, total: 210, cancelled: true) == "Stopped after 34 of 210.")
    }
}
