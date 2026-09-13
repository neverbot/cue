import CueCore
import CuePlayer
import Foundation
import Testing

@Suite struct ChapterTimelineTests {
    static let chapters = [
        Chapter(title: "Intro", start: 0, end: 45),
        Chapter(title: "Middle", start: 45, end: 150),
        Chapter(title: "Outro", start: 150, end: 200),
    ]
    let timeline = ChapterTimeline(chapters: chapters, duration: 200)

    @Test func findsTheChapterAtAPosition() {
        #expect(timeline.chapter(at: 0)?.title == "Intro")
        #expect(timeline.chapter(at: 44.9)?.title == "Intro")
        #expect(timeline.chapter(at: 45)?.title == "Middle")
        #expect(timeline.chapter(at: 199)?.title == "Outro")
    }

    @Test func hasNoChapterWithoutAny() {
        #expect(ChapterTimeline(chapters: [], duration: 200).chapter(at: 10) == nil)
        #expect(ChapterTimeline(chapters: [], duration: 200).isEmpty)
    }

    @Test func seeksToTheNextChapterStart() {
        #expect(timeline.nextStart(from: 10) == 45)
        #expect(timeline.nextStart(from: 45) == 150)
    }

    @Test func hasNoNextChapterInTheLastOne() {
        #expect(timeline.nextStart(from: 160) == nil)
    }

    /// mpv's own rule, and IINA's: going back from the middle of a chapter restarts it; going back near its start
    /// goes to the chapter before.
    @Test func restartsTheCurrentChapterWhenWellIntoIt() {
        #expect(timeline.previousStart(from: 100) == 45)
    }

    @Test func stepsBackAChapterNearItsStart() {
        #expect(timeline.previousStart(from: 46) == 0)
    }

    @Test func hasNowhereToGoBackToAtTheStart() {
        #expect(timeline.previousStart(from: 1) == nil)
    }

    /// The first chapter of every real list starts at zero, and restarting it is what any other chapter would do.
    @Test func restartsTheFirstChapterWhenWellIntoIt() {
        #expect(timeline.previousStart(from: 100) == 45)
        #expect(timeline.previousStart(from: 30) == 0)
    }

    @Test func placesTicksAsFractionsOfTheDuration() {
        #expect(timeline.tickFractions == [0.225, 0.75])
    }

    @Test func hasNoTicksWithoutADuration() {
        #expect(ChapterTimeline(chapters: Self.chapters, duration: nil).tickFractions.isEmpty)
    }
}
