import CueCore
import CuePlayer
import Foundation
import Testing

@Suite struct SubtitleSessionTests {
    static let english = CaptionTrack(
        languageCode: "en",
        displayName: "English",
        isAutomatic: false,
        baseURL: URL(string: "https://www.youtube.com/api/timedtext?v=dQw4w9WgXcQ&lang=en")!
    )
    static let automatic = CaptionTrack(
        languageCode: "en",
        displayName: "English",
        isAutomatic: true,
        baseURL: URL(string: "https://www.youtube.com/api/timedtext?v=dQw4w9WgXcQ&lang=en&kind=asr")!
    )
    let videoID = VideoID("12345678-_a")!

    func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "cue-subtitle-tests-\(UUID().uuidString)")
    }

    @Test func producesOneMpvPropertyPerStyleValue() {
        let names = SubtitleStyle().properties.map(\.name)
        #expect(names == [
            "sub-scale", "sub-color", "sub-border-size", "sub-back-color", "sub-border-style", "sub-pos",
        ])
    }

    @Test func scalesWithTheChosenSize() {
        var style = SubtitleStyle()
        style.size = .large
        #expect(style.properties.first { $0.name == "sub-scale" }?.value == "1.4")
        style.size = .small
        #expect(style.properties.first { $0.name == "sub-scale" }?.value == "0.8")
    }

    /// The box is one setting expressed through two mpv properties, and the colour is the half that does nothing on
    /// its own: nothing paints `sub-back-color` while the border style is the outlined default. Both are asserted in
    /// both states, so a build that sets only the colour again fails here rather than on screen.
    @Test func turnsTheBackgroundBoxOnAndOff() {
        var style = SubtitleStyle()
        #expect(style.properties.first { $0.name == "sub-back-color" }?.value == "#00000000")
        #expect(style.properties.first { $0.name == "sub-border-style" }?.value == "outline-and-shadow")
        style.hasBackgroundBox = true
        #expect(style.properties.first { $0.name == "sub-back-color" }?.value == "#80000000")
        #expect(style.properties.first { $0.name == "sub-border-style" }?.value == "background-box")
    }

    @Test func buildsTheLoadCommandsInOrder() {
        var session = SubtitleSession()
        let file = URL(fileURLWithPath: "/tmp/cue-subtitles/en.vtt")
        let commands = session.select(Self.english, file: file)

        #expect(commands.first == .addSubtitle(fileURL: file))
        #expect(commands.dropFirst().first == .selectSubtitle(id: SubtitleSession.externalTrackID))
        #expect(commands.contains(.setSubtitleDelay(seconds: 0)))
        #expect(commands.contains(.setSubtitleProperty(name: "sub-scale", value: "1.0")))
        #expect(session.selected == Self.english)
    }

    /// Only ever one external subtitle: the previous one is removed first, which is what keeps its id predictable.
    @Test func replacesThePreviousTrackBeforeAddingAnother() {
        var session = SubtitleSession()
        _ = session.select(Self.english, file: URL(fileURLWithPath: "/tmp/a.vtt"))
        let commands = session.select(Self.automatic, file: URL(fileURLWithPath: "/tmp/b.vtt"))

        #expect(commands.first == .removeSubtitles)
        #expect(session.selected == Self.automatic)
    }

    @Test func disablingRemovesTheTrackButKeepsTheSettings() {
        var session = SubtitleSession()
        session.delay = -0.4
        session.style.size = .large
        _ = session.select(Self.english, file: URL(fileURLWithPath: "/tmp/a.vtt"))

        let commands = session.disable()

        #expect(commands == [.selectSubtitle(id: nil), .removeSubtitles])
        #expect(session.selected == nil)
        #expect(session.delay == -0.4)
        #expect(session.style.size == .large)
    }

    @Test func carriesTheDelayIntoTheNextTrack() {
        var session = SubtitleSession()
        session.delay = 0.25
        let commands = session.select(Self.english, file: URL(fileURLWithPath: "/tmp/a.vtt"))
        #expect(commands.contains(.setSubtitleDelay(seconds: 0.25)))
    }

    @Test func namesTheFileByVideoAndTrack() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = try SubtitleSession.write(
            cues: [CaptionCue(start: 0, end: 1, text: "hello")],
            for: Self.automatic, videoID: videoID, in: directory
        )

        #expect(file.lastPathComponent == "12345678-_a.en-auto.vtt")
        #expect(try String(contentsOf: file, encoding: .utf8).hasPrefix("WEBVTT\n"))
    }

    /// Subtitle files are a record of what is being watched: nobody else on the Mac gets to read them.
    @Test func keepsTheSubtitleDirectoryPrivate() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try SubtitleSession.write(cues: [], for: Self.english, videoID: videoID, in: directory)

        let mode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        #expect(mode?.int16Value == 0o700)
    }
}
