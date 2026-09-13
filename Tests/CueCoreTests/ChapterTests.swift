import Foundation
import Testing
@testable import CueCore

@Suite struct ChapterTests {
    func fixtureChapters(duration: Double? = 200) throws -> [Chapter] {
        WatchPageChapters.chapters(inHTML: try Fixture.string("watch-page-chapters.html"), duration: duration)
    }

    @Test func readsChaptersFromTheWatchPage() throws {
        let chapters = try fixtureChapters()
        #expect(chapters.count == 3)
        #expect(chapters.map(\.title) == ["Intro", "The middle", "Outro"])
        #expect(chapters.map(\.start) == [0, 45, 150])
    }

    @Test func closesEachChapterAtTheNextStart() throws {
        #expect(try fixtureChapters()[0].end == 45)
        #expect(try fixtureChapters()[1].end == 150)
    }

    @Test func closesTheLastChapterAtTheDuration() throws {
        #expect(try fixtureChapters()[2].end == 200)
        #expect(try fixtureChapters(duration: nil)[2].end == nil)
    }

    /// A video with both lists has chapters its author wrote; those win over the machine's.
    @Test func prefersTheAuthorsChaptersOverAutomaticOnes() throws {
        #expect(try fixtureChapters().contains { $0.title == "Machine one" } == false)
    }

    @Test func usesAutomaticChaptersWhenThereAreNoOthers() throws {
        let html = try Fixture.string("watch-page-chapters.html")
            .replacingOccurrences(of: "DESCRIPTION_CHAPTERS", with: "SOMETHING_ELSE")
        let chapters = WatchPageChapters.chapters(inHTML: html, duration: 200)
        #expect(chapters.map(\.title) == ["Machine one"])
    }

    /// The live page for a video without chapters carries the renderer with no `markersMap` at all.
    @Test func hasNoChaptersWhenTheRendererIsEmpty() {
        let html = #"<script>var ytInitialData = {"playerOverlays":{"playerOverlayRenderer":{"decoratedPlayerBarRenderer":"#
            + #"{"decoratedPlayerBarRenderer":{"playerBar":{"multiMarkersPlayerBarRenderer":{"visibleOnLoad":{"key":""}}}}}}}};</script>"#
        #expect(WatchPageChapters.chapters(inHTML: html, duration: 200).isEmpty)
    }

    @Test func hasNoChaptersWhenThePageHasNoOverlay() throws {
        #expect(WatchPageChapters.chapters(inHTML: try Fixture.string("watch-page-snippet.html"), duration: 200).isEmpty)
    }

    /// InnerTube writes the same field as a number in one place and a string in another.
    @Test func acceptsAStartWrittenAsAString() throws {
        #expect(try fixtureChapters()[1].start == 45)
    }

    @Test func readsTimestampsFromADescription() {
        let description = "Thanks for watching\n0:00 Intro\n1:30 Middle part\n1:02:03 The long tail\nsubscribe"
        let chapters = Chapter.list(inDescription: description, duration: 4000)
        #expect(chapters.map(\.title) == ["Intro", "Middle part", "The long tail"])
        #expect(chapters.map(\.start) == [0, 90, 3723])
        #expect(chapters[0].end == 90)
        #expect(chapters[2].end == 4000)
    }

    /// A list that does not start at zero is a list of references, not a table of contents.
    @Test func requiresTheFirstDescriptionTimestampToBeZero() {
        #expect(Chapter.list(inDescription: "1:00 Later\n2:00 Even later", duration: 300).isEmpty)
    }

    @Test func ignoresDescriptionTimestampsThatGoBackwards() {
        let chapters = Chapter.list(inDescription: "0:00 One\n2:00 Two\n1:00 Back\n3:00 Three", duration: 300)
        #expect(chapters.map(\.title) == ["One", "Two", "Three"])
    }

    @Test func dropsDescriptionTimestampsPastTheEnd() {
        let chapters = Chapter.list(inDescription: "0:00 One\n2:00 Two\n9:00 Way past", duration: 300)
        #expect(chapters.map(\.title) == ["One", "Two"])
    }
}
