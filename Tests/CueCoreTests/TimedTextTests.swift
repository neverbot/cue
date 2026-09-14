import Foundation
import Testing
@testable import CueCore

@Suite struct TimedTextTests {
    func fixtureCues() throws -> [CaptionCue] {
        try TimedText.cues(fromJSON3: Fixture.data("timedtext-json3.json"))
    }

    @Test func readsCuesFromTheFixture() throws {
        let cues = try fixtureCues()
        #expect(cues.count == 4)
        #expect(cues[0].text == "[music]")
        #expect(cues[0].start == 1.36)
        #expect(cues[0].end == 3.04)
    }

    /// Events without `segs` position windows and pens; they are not captions.
    @Test func skipsEventsWithoutSegments() throws {
        #expect(try fixtureCues().contains { $0.start == 0 } == false)
    }

    @Test func joinsSegmentsIntoOneCue() throws {
        #expect(try fixtureCues()[1].text == "We're no strangers to love")
    }

    @Test func skipsCuesThatAreOnlyWhitespace() throws {
        #expect(try fixtureCues().contains { $0.start == 5 } == false)
    }

    /// An event without a duration lasts until the next thing happens on screen, which is the next event's start —
    /// even when that event is one of the ones dropped above.
    @Test func endsACueAtTheNextEventWhenNoDurationIsGiven() throws {
        #expect(try fixtureCues()[1].end == 5)
    }

    @Test func keepsLineBreaksInsideACue() throws {
        let cue = try fixtureCues()[2]
        #expect(cue.text == "You know the rules\nand so do I")
        #expect(cue.lines == ["You know the rules", "and so do I"])
    }

    @Test func clampsACueThatWouldOverlapTheNextOne() throws {
        let json = #"{"events":[{"tStartMs":0,"dDurationMs":9000,"segs":[{"utf8":"first"}]},"#
            + #"{"tStartMs":2000,"dDurationMs":1000,"segs":[{"utf8":"second"}]}]}"#
        let cues = try TimedText.cues(fromJSON3: Data(json.utf8))
        #expect(cues[0].end == 2)
        #expect(cues[1].end == 3)
    }

    @Test func reportsUnreadableTimedText() {
        #expect(throws: ExtractionError.unexpectedResponse) {
            try TimedText.cues(fromJSON3: Data("<html>not json</html>".utf8))
        }
    }
}

@Suite struct SubtitleWriterTests {
    static let cues = [
        CaptionCue(start: 1.36, end: 3.04, text: "[music]"),
        CaptionCue(start: 3.04, end: 5, text: "We're no strangers to love"),
    ]

    @Test func writesSrtIndicesAndCommaDecimals() {
        #expect(SubtitleWriter.srt(Self.cues) == """
        1
        00:00:01,360 --> 00:00:03,040
        [music]

        2
        00:00:03,040 --> 00:00:05,000
        We're no strangers to love

        """)
    }

    @Test func writesVttWithAHeaderAndDotDecimals() {
        #expect(SubtitleWriter.vtt(Self.cues) == """
        WEBVTT

        1
        00:00:01.360 --> 00:00:03.040
        [music]

        2
        00:00:03.040 --> 00:00:05.000
        We're no strangers to love

        """)
    }

    @Test func writesHoursInBothFormats() {
        let cues = [CaptionCue(start: 3661.5, end: 3662, text: "late")]
        #expect(SubtitleWriter.srt(cues).contains("01:01:01,500 --> 01:01:02,000"))
        #expect(SubtitleWriter.vtt(cues).contains("01:01:01.500 --> 01:01:02.000"))
    }

    @Test func keepsLineBreaks() {
        let cues = [CaptionCue(start: 0, end: 1, text: "one\ntwo")]
        #expect(SubtitleWriter.srt(cues).contains("one\ntwo"))
    }

    @Test func writesAnEmptyTrack() {
        #expect(SubtitleWriter.srt([]) == "")
        #expect(SubtitleWriter.vtt([]) == "WEBVTT\n")
    }

    @Test func roundsMillisecondsDown() {
        #expect(SubtitleWriter.srt([CaptionCue(start: 1.2349, end: 2, text: "x")]).contains("00:00:01,234"))
    }

    @Test func separatesCuesWithABlankLine() {
        #expect(SubtitleWriter.srt(Self.cues).contains("[music]\n\n2\n"))
    }

    @Test func namesTheFileExtensionOfEachExportFormat() {
        #expect(ExportFormat.srt.fileExtension == "srt")
        #expect(ExportFormat.vtt.fileExtension == "vtt")
    }

    /// Exporting goes through one entry point, so the caller picks a format instead of picking a writer.
    @Test func writesEachExportFormatThroughOneEntryPoint() {
        let srt = SubtitleWriter.srt(Self.cues)
        let vtt = SubtitleWriter.vtt(Self.cues)
        #expect(SubtitleWriter.text(Self.cues, as: .srt) == srt)
        #expect(SubtitleWriter.text(Self.cues, as: .vtt) == vtt)
    }
}
