import CueCore
import CuePlayer
import Foundation
import Testing

@Suite struct SubtitleCommandTests {
    let file = URL(fileURLWithPath: "/tmp/cue-subtitles/en.vtt")

    @Test func addsAnExternalSubtitleAndSelectsIt() {
        #expect(PlayerCommand.addSubtitle(fileURL: file).mpvArguments == ["sub-add", "/tmp/cue-subtitles/en.vtt", "select"])
    }

    @Test func removesTheLoadedSubtitle() {
        #expect(PlayerCommand.removeSubtitles.mpvArguments == ["sub-remove"])
    }

    @Test func selectsASubtitleById() {
        #expect(PlayerCommand.selectSubtitle(id: 1).mpvArguments == ["set", "sid", "1"])
    }

    @Test func disablesSubtitles() {
        #expect(PlayerCommand.selectSubtitle(id: nil).mpvArguments == ["set", "sid", "no"])
    }

    @Test func setsTheDelay() {
        #expect(PlayerCommand.setSubtitleDelay(seconds: -0.5).mpvArguments == ["set", "sub-delay", "-0.5"])
    }

    @Test func adjustsTheDelay() {
        #expect(PlayerCommand.adjustSubtitleDelay(by: 0.1).mpvArguments == ["add", "sub-delay", "0.1"])
    }

    @Test func setsASubtitleProperty() {
        #expect(PlayerCommand.setSubtitleProperty(name: "sub-scale", value: "1.2").mpvArguments == ["set", "sub-scale", "1.2"])
    }

    /// Chapters and panels are window business: the engine has nothing to do with them.
    @Test func leavesWindowCommandsToTheWindow() {
        for command in [PlayerCommand.nextChapter, .previousChapter, .toggleChaptersPanel, .toggleSubtitlesPanel, .toggleMiniPlayer] {
            #expect(command.mpvArguments == nil)
        }
    }

    @Test func bindsTheDelayKeys() {
        #expect(KeyBindings.standard.command(for: KeyPress(.character("z"))) == .adjustSubtitleDelay(by: -KeyBindings.subtitleDelayStep))
        #expect(KeyBindings.standard.command(for: KeyPress(.character("x"))) == .adjustSubtitleDelay(by: KeyBindings.subtitleDelayStep))
    }

    @Test func bindsChapterJumpsToTheOptionArrows() {
        #expect(KeyBindings.standard.command(for: KeyPress(.rightArrow, modifiers: .option)) == .nextChapter)
        #expect(KeyBindings.standard.command(for: KeyPress(.leftArrow, modifiers: .option)) == .previousChapter)
        // Unmodified arrows still seek.
        #expect(KeyBindings.standard.command(for: KeyPress(.rightArrow)) == .seekRelative(seconds: KeyBindings.seekStep))
    }

    @Test func bindsThePanelKeys() {
        #expect(KeyBindings.standard.command(for: KeyPress(.character("c"))) == .toggleChaptersPanel)
        #expect(KeyBindings.standard.command(for: KeyPress(.character("s"))) == .toggleSubtitlesPanel)
    }

    /// ⌘-shortcuts belong to the main menu; a binding must not swallow them.
    @Test func stillIgnoresCommandModifiedPresses() {
        #expect(KeyBindings.standard.command(for: KeyPress(.character("s"), modifiers: .command)) == nil)
        #expect(KeyBindings.standard.command(for: KeyPress(.character("f"), modifiers: [.control, .command])) == nil)
    }
}
