@testable import CuePlayer
import Foundation
import Testing

@Suite struct PlayerOptionsTests {
    /// Pins the full, ordered option list: `baseline()` is security-relevant (`config=no` keeps mpv from reading the
    /// user's `~/.config/mpv/mpv.conf`, which could re-enable Lua scripts and get the hardened app killed) and
    /// `PlayerController` depends on `keep-open=yes` for its early-end logic. A spot check would stay green after
    /// any of those were dropped by accident, so this asserts the exact list instead.
    @Test func matchesTheExactHardenedOptionList() {
        #expect(PlayerOptions.baseline() == [
            MPVOption("vo", "libmpv"),
            MPVOption("hwdec", "videotoolbox"),
            MPVOption("config", "no"),
            MPVOption("load-scripts", "no"),
            MPVOption("osc", "no"),
            MPVOption("load-stats-overlay", "no"),
            MPVOption("load-console", "no"),
            MPVOption("load-auto-profiles", "no"),
            MPVOption("load-select", "no"),
            MPVOption("load-positioning", "no"),
            MPVOption("load-commands", "no"),
            MPVOption("load-context-menu", "no"),
            MPVOption("ytdl", "no"),
            MPVOption("input-default-bindings", "no"),
            MPVOption("input-vo-keyboard", "no"),
            MPVOption("terminal", "no"),
            MPVOption("osd-level", "0"),
            MPVOption("idle", "yes"),
            MPVOption("keep-open", "yes"),
            MPVOption("volume-max", "100"),
        ])
    }

    @Test func keepsEveryScriptOff() {
        let options = PlayerOptions.baseline()
        let scriptSwitches = options.filter { $0.name.hasPrefix("load-") }
        // Not `== 8`: that would fail every time a hardening switch is added, penalizing the safer direction.
        #expect(scriptSwitches.count >= 8)
        #expect(scriptSwitches.allSatisfy { $0.value == "no" })
        #expect(!options.contains { $0.name == "script" || $0.name == "scripts" })
    }

    /// Pinned exactly, like the baseline: every name here was validated against Cue's libmpv on a real stream, and a
    /// renamed option (`cache-dir` is not one) fails the whole stream at load time rather than at compile time.
    @Test func putsTheStreamCacheOnDiskWithALargerCap() {
        #expect(PlayerOptions.streamCache(directory: "/tmp/cache") == [
            MPVOption("cache-on-disk", "yes"),
            MPVOption("demuxer-cache-dir", "/tmp/cache"),
            MPVOption("demuxer-max-bytes", "512MiB"),
            MPVOption("cache-pause-wait", "3"),
        ])
    }

    @Test func keepsTheStreamCacheOutOfTheBaseline() {
        // Tests build engines from the baseline and must not write a cache anywhere.
        #expect(!PlayerOptions.baseline().contains { $0.name == "cache-on-disk" || $0.name == "demuxer-cache-dir" })
    }

    @Test func observesHowFarTheStreamHasLoaded() {
        #expect(PlayerOptions.observedProperties.contains { $0.name == "demuxer-cache-time" && $0.format == .double })
    }

    @Test func addsAudioOutputOnlyWhenGiven() {
        #expect(!PlayerOptions.baseline().contains { $0.name == "ao" })
        #expect(PlayerOptions.baseline(videoOutput: "null", audioOutput: "null").contains(MPVOption("ao", "null")))
    }

    @Test func quotesPerFileOptions() {
        let request = LoadRequest(stream: TestStreams.stream(), start: 42.5)
        #expect(request.arguments == [
            "loadfile", "https://media.example.invalid/video.mp4", "replace", "-1",
            "audio-files-append=%39%https://media.example.invalid/audio.m4a,user-agent=%34%TestBrowser/1.0 (Test, like Gecko),start=42.5",
        ])
    }

    @Test func omitsOptionsALocalFileDoesNotNeed() {
        let request = LoadRequest(stream: PlayableStream(fileURL: URL(fileURLWithPath: "/tmp/test clip.mp4")), start: 0)
        #expect(request.arguments == ["loadfile", "/tmp/test clip.mp4", "replace"])
    }
}
