import Foundation
import Testing
@testable import CueCore

@Suite struct StoryboardSpecTests {
    /// The shape of a real spec, with a synthetic video id and obviously fake `sqp`/`sigh` values.
    static let spec = "https://i.ytimg.com/sb/12345678-_a/storyboard3_L$L/$N.jpg?sqp=test"
        + "|48#27#100#10#10#0#default#rs$test"
        + "|80#45#108#10#10#2000#M$M#rs$test"
        + "|160#90#108#5#5#2000#M$M#rs$test"

    func parsed() throws -> StoryboardSpec {
        try #require(StoryboardSpec(Self.spec))
    }

    @Test func parsesEveryLevel() throws {
        let spec = try parsed()
        #expect(spec.levels.count == 3)
        let level = spec.levels[1]
        #expect(level.index == 1)
        #expect(level.width == 80)
        #expect(level.height == 45)
        #expect(level.frameCount == 108)
        #expect(level.columns == 10)
        #expect(level.rows == 10)
        #expect(level.intervalMilliseconds == 2000)
        #expect(level.nameTemplate == "M$M")
        #expect(level.signature == "rs$test")
    }

    @Test func refusesAStringWithoutLevels() {
        #expect(StoryboardSpec("https://i.ytimg.com/sb/12345678-_a/storyboard3_L$L/$N.jpg") == nil)
        #expect(StoryboardSpec("") == nil)
    }

    /// A level that cannot be parsed is dropped, but the ones that survive keep the position they had in the spec:
    /// the index is what `$L` becomes in the sheet URL, so renumbering the survivors would request a different
    /// level from the one whose dimensions were parsed. Here the first level is malformed, so the survivor is
    /// still level 1.
    @Test func skipsALevelWithTooFewFields() throws {
        let spec = try #require(StoryboardSpec("https://example.invalid/$L/$N.jpg|48#27#100|80#45#108#10#10#2000#M$M#rs$test"))
        #expect(spec.levels.count == 1)
        #expect(spec.levels[0].index == 1)
        #expect(spec.sheetURL(level: spec.levels[0], sheet: 0)?.absoluteString == "https://example.invalid/1/M0.jpg?sigh=rs$test")
    }

    @Test func countsFramesPerSheetAndSheets() throws {
        let spec = try parsed()
        #expect(spec.levels[1].framesPerSheet == 100)
        #expect(spec.levels[1].sheetCount == 2)
        #expect(spec.levels[2].framesPerSheet == 25)
        #expect(spec.levels[2].sheetCount == 5)
    }

    @Test func buildsASheetURL() throws {
        let spec = try parsed()
        let url = try #require(spec.sheetURL(level: spec.levels[2], sheet: 3))
        #expect(url.absoluteString == "https://i.ytimg.com/sb/12345678-_a/storyboard3_L2/M3.jpg?sqp=test&sigh=rs$test")
    }

    /// Dropping the `rs$` prefix from the signature makes YouTube answer 403, so it is part of the value.
    @Test func keepsTheSignaturePrefix() throws {
        let spec = try parsed()
        let url = try #require(spec.sheetURL(level: spec.levels[0], sheet: 0))
        #expect(url.query?.contains("sigh=rs$test") == true)
    }

    @Test func startsTheQueryWhenTheBaseHasNone() throws {
        let spec = try #require(StoryboardSpec("https://example.invalid/$L/$N.jpg|48#27#100#10#10#0#default#rs$test"))
        let url = try #require(spec.sheetURL(level: spec.levels[0], sheet: 0))
        #expect(url.absoluteString == "https://example.invalid/0/default.jpg?sigh=rs$test")
    }

    @Test func picksTheWidestLevelAsTheBestOne() throws {
        let spec = try parsed()
        #expect(spec.bestLevel?.width == 160)
    }

    @Test func usesTheDeclaredInterval() throws {
        #expect(try parsed().levels[2].interval(duration: 213) == 2)
    }

    /// The overview level declares no interval: its frames are spread across the whole video instead.
    @Test func spreadsTheOverviewLevelAcrossTheDuration() throws {
        #expect(try parsed().levels[0].interval(duration: 200) == 2)
    }

    @Test func hasNoIntervalWithoutADurationOrADeclaredOne() throws {
        #expect(try parsed().levels[0].interval(duration: nil) == nil)
        #expect(try parsed().frame(at: 10, duration: nil, level: parsed().levels[0]) == nil)
    }

    @Test func mapsAPositionToItsSheetRowAndColumn() throws {
        let spec = try parsed()
        let frame = try #require(spec.frame(at: 61, duration: 213, level: spec.levels[2]))
        #expect(frame.sheet == 1)
        #expect(frame.column == 0)
        #expect(frame.row == 1)
        #expect(frame.width == 160)
        #expect(frame.height == 90)
        #expect(frame.url.absoluteString.hasSuffix("storyboard3_L2/M1.jpg?sqp=test&sigh=rs$test"))
    }

    @Test func clampsAPositionPastTheEndToTheLastFrame() throws {
        let spec = try parsed()
        let frame = try #require(spec.frame(at: 10_000, duration: 213, level: spec.levels[2]))
        #expect(frame.sheet == 4)
        #expect(frame.column == 2)
        #expect(frame.row == 1)
    }

    @Test func clampsANegativePositionToTheFirstFrame() throws {
        let spec = try parsed()
        let frame = try #require(spec.frame(at: -30, duration: 213, level: spec.levels[1]))
        #expect(frame.sheet == 0)
        #expect(frame.column == 0)
        #expect(frame.row == 0)
    }
}
