import CueCore
import CuePlayer
import Foundation
import Testing

/// The stream URLs here are obviously fake: a real one is signed and carries the requester's address.
enum TestAudioTracks {
    static let original = AudioTrackOption(
        track: AudioTrack(id: "en.4", displayName: "English original", isDefault: true),
        url: URL(string: "https://media.example.invalid/audio-en.m4a")!
    )
    static let spanish = AudioTrackOption(
        track: AudioTrack(id: "es-ES.3", displayName: "Spanish (Spain)", isDefault: false),
        url: URL(string: "https://media.example.invalid/audio-es.m4a")!
    )
    static let german = AudioTrackOption(
        track: AudioTrack(id: "de.2", displayName: "German", isDefault: false),
        url: URL(string: "https://media.example.invalid/audio-de.m4a")!
    )

    static func dubbedStream() -> PlayableStream {
        PlayableStream(
            videoID: TestStreams.videoID,
            title: "Dubbed test stream",
            videoURL: URL(string: "https://media.example.invalid/video.mp4")!,
            audioURL: original.url,
            duration: 213,
            audioTracks: [original, spanish],
            selectedAudioTrackID: original.id
        )
    }
}

@Suite struct AudioTrackCommandTests {
    @Test func addsAnExternalAudioTrackAndSelectsIt() {
        #expect(PlayerCommand.addAudioTrack(url: TestAudioTracks.spanish.url).mpvArguments
            == ["audio-add", "https://media.example.invalid/audio-es.m4a", "select"])
    }

    @Test func removesTheLoadedAudioTrack() {
        #expect(PlayerCommand.removeAudioTracks.mpvArguments == ["audio-remove"])
    }

    @Test func selectsAnAudioTrackById() {
        #expect(PlayerCommand.selectAudioTrack(id: AudioTrackSession.externalTrackID).mpvArguments == ["set", "aid", "1"])
    }

    /// The audio page opens from the keyboard like the other two.
    @Test func bindsTheAudioPageKey() {
        #expect(KeyBindings.standard.command(for: KeyPress(.character("a"))) == .toggleAudioInspector)
        #expect(KeyBindings.standard.command(for: KeyPress(.character("a"), modifiers: .command)) == nil)
    }
}

@Suite struct AudioTrackSessionTests {
    /// The load already attached one external audio track, so the previous one comes off before the next goes on —
    /// otherwise two languages would play at once.
    @Test func replacesTheLoadedTrackInOneMove() {
        var session = AudioTrackSession(stream: TestAudioTracks.dubbedStream())
        let commands = session.select(TestAudioTracks.spanish)

        #expect(commands == [
            .removeAudioTracks,
            .addAudioTrack(url: TestAudioTracks.spanish.url),
            .selectAudioTrack(id: AudioTrackSession.externalTrackID),
        ])
        #expect(session.selectedID == "es-ES.3")
        #expect(session.selected == TestAudioTracks.spanish)
    }

    /// Re-adding the language already playing would drop a moment of sound to arrive back where it started.
    @Test func doesNothingForTheTrackAlreadyPlaying() {
        var session = AudioTrackSession(stream: TestAudioTracks.dubbedStream())
        #expect(session.select(TestAudioTracks.original).isEmpty)
        #expect(session.selectedID == "en.4")
    }

    /// A track this video does not offer has no stream to add.
    @Test func refusesATrackTheVideoDoesNotOffer() {
        var session = AudioTrackSession(stream: TestAudioTracks.dubbedStream())
        #expect(session.select(TestAudioTracks.german).isEmpty)
        #expect(session.selectedID == "en.4")
    }

    @Test func readsWhatTheStreamOffers() {
        let session = AudioTrackSession(stream: TestAudioTracks.dubbedStream())
        #expect(session.tracks.map(\.id) == ["en.4", "es-ES.3"])
        #expect(session.offersAChoice)
        #expect(session.option(id: "es-ES.3") == TestAudioTracks.spanish)
        #expect(session.option(id: "fr.1") == nil)
    }

    /// A video with one soundtrack carries no languages at all, and offers no choice to make.
    @Test func offersNoChoiceForASingleTrackVideo() {
        let session = AudioTrackSession(stream: TestStreams.stream())
        #expect(session.tracks.isEmpty)
        #expect(session.offersAChoice == false)
        #expect(session.selected == nil)
    }
}

@MainActor
@Suite struct AudioTrackSwitchTests {
    /// The point of carrying every language through the resolution: switching is a swap of the external audio track
    /// on the file that is already playing. Nothing is loaded again, nothing is asked of YouTube, and the position
    /// and the pause state come out the other side untouched.
    @Test func switchingNeitherReloadsTheFileNorReResolves() async throws {
        let engine = FakeEngine()
        let resolver = FakeResolver([.success(TestAudioTracks.dubbedStream())])
        let controller = PlayerController(engine: engine, resolver: resolver, resumeStore: InMemoryResumeStore())

        await controller.open(.video(TestStreams.videoID))
        engine.emit(.fileLoaded, .playbackRestarted, .position(42), .paused(true))
        let loadsBefore = engine.loaded.count

        var session = AudioTrackSession(stream: controller.state.stream)
        for command in session.select(TestAudioTracks.spanish) {
            controller.perform(command)
        }

        #expect(engine.loaded.count == loadsBefore)
        #expect(resolver.requests == [TestStreams.videoID])
        #expect(controller.state.position == 42)
        #expect(controller.state.isPaused)
        #expect(engine.commands.suffix(3) == [
            .removeAudioTracks,
            .addAudioTrack(url: TestAudioTracks.spanish.url),
            .selectAudioTrack(id: AudioTrackSession.externalTrackID),
        ])
    }
}
