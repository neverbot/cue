import CueCore
import CueQueue
import Foundation
import Testing

@Suite struct AudioTrackPresentationTests {
    static func option(_ id: String, _ name: String, isDefault: Bool = false) -> AudioTrackOption {
        AudioTrackOption(
            track: AudioTrack(id: id, displayName: name, isDefault: isDefault),
            url: URL(string: "https://media.example.invalid/audio-\(id).m4a")!
        )
    }

    var dubbed: [AudioTrackOption] {
        [
            Self.option("en.4", "English original", isDefault: true),
            Self.option("es-ES.3", "Spanish (Spain)"),
            Self.option("de.2", "German"),
        ]
    }

    /// YouTube's order is kept, and the row playing now is the one marked.
    @Test func listsEveryLanguageWithTheOnePlayingMarked() {
        let rows = AudioTrackPresentation.rows(for: dubbed, selected: "es-ES.3")
        #expect(rows.map(\.title) == ["English original", "Spanish (Spain)", "German"])
        #expect(rows.map(\.isSelected) == [false, true, false])
        #expect(AudioTrackPresentation.selectedRow(in: rows) == 1)
    }

    /// One track is not a choice: the page says so in words rather than showing a list of one.
    @Test func listsNothingForASingleTrackVideo() {
        let rows = AudioTrackPresentation.rows(for: [Self.option("en.4", "English original", isDefault: true)], selected: "en.4")
        #expect(rows.isEmpty)
    }

    /// A video that declares no languages at all is the same case, and gets the same page.
    @Test func listsNothingWhenTheVideoDeclaresNoLanguages() {
        #expect(AudioTrackPresentation.rows(for: [], selected: nil).isEmpty)
    }

    /// Nothing is marked while the playing track is not one of the listed ones.
    @Test func marksNoRowWhenNoneIsPlaying() {
        let rows = AudioTrackPresentation.rows(for: dubbed, selected: nil)
        #expect(rows.allSatisfy { !$0.isSelected })
        #expect(AudioTrackPresentation.selectedRow(in: rows) == nil)
    }
}
