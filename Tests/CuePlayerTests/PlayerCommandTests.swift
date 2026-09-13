@testable import CuePlayer
import Testing

@Suite struct PlayerCommandTests {
    let bindings = KeyBindings.standard

    @Test func mapsIINAStyleDefaults() {
        #expect(bindings.command(for: KeyPress(.character(" "))) == .togglePause)
        #expect(bindings.command(for: KeyPress(.leftArrow)) == .seekRelative(seconds: -5))
        #expect(bindings.command(for: KeyPress(.rightArrow)) == .seekRelative(seconds: 5))
        #expect(bindings.command(for: KeyPress(.upArrow)) == .adjustVolume(by: 5))
        #expect(bindings.command(for: KeyPress(.downArrow)) == .adjustVolume(by: -5))
        #expect(bindings.command(for: KeyPress(.character("f"))) == .toggleFullScreen)
        #expect(bindings.command(for: KeyPress(.character("m"))) == .toggleMute)
    }

    @Test func ignoresCaseForLetters() {
        #expect(bindings.command(for: KeyPress(.character("F"))) == .toggleFullScreen)
    }

    @Test func leavesModifiedAndUnknownKeysToTheMenu() {
        #expect(bindings.command(for: KeyPress(.character("w"), modifiers: .command)) == nil)
        #expect(bindings.command(for: KeyPress(.character("f"), modifiers: [.command, .control])) == nil)
        #expect(bindings.command(for: KeyPress(.character("q"))) == nil)
    }

    @Test func buildsMPVCommands() {
        #expect(PlayerCommand.togglePause.mpvArguments == ["cycle", "pause"])
        #expect(PlayerCommand.seekRelative(seconds: -5).mpvArguments == ["seek", "-5.0", "relative"])
        #expect(PlayerCommand.seekAbsolute(seconds: 42.5).mpvArguments == ["seek", "42.5", "absolute"])
        #expect(PlayerCommand.seekAbsolute(seconds: -3).mpvArguments == ["seek", "0.0", "absolute"])
        #expect(PlayerCommand.adjustVolume(by: 5).mpvArguments == ["add", "volume", "5.0"])
        #expect(PlayerCommand.setVolume(140).mpvArguments == ["set", "volume", "100.0"])
        #expect(PlayerCommand.toggleMute.mpvArguments == ["cycle", "mute"])
        #expect(PlayerCommand.toggleFullScreen.mpvArguments == nil)
        #expect(PlayerCommand.close.mpvArguments == nil)
    }
}
