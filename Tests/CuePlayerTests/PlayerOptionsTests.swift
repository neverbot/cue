@testable import CuePlayer
import Foundation
import Testing

@Suite struct PlayerOptionsTests {
    @Test func keepsEveryScriptOff() {
        let options = PlayerOptions.baseline()
        #expect(options.contains(MPVOption("vo", "libmpv")))
        #expect(options.contains(MPVOption("load-scripts", "no")))
        #expect(options.contains(MPVOption("osc", "no")))
        let scriptSwitches = options.filter { $0.name.hasPrefix("load-") }
        #expect(scriptSwitches.count == 8)
        #expect(scriptSwitches.allSatisfy { $0.value == "no" })
        #expect(!options.contains { $0.name == "script" || $0.name == "scripts" })
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
