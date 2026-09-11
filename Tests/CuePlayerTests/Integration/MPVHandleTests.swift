import CueMPV
import Foundation
import Testing

/// Headless mpv core with the synthetic clip (`vo=null`, `ao=null`). Opt in with `CUE_MPV_TESTS=1`.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CUE_MPV_TESTS"] == "1"))
struct MPVHandleTests {
    static func makeHandle(videoOutput: String, keepOpen: Bool, recorder: EventRecorder) throws -> MPVHandle {
        let handle = try MPVHandle()
        for (name, value) in [
            ("vo", videoOutput), ("ao", "null"), ("config", "no"), ("terminal", "no"), ("load-scripts", "no"),
            ("osc", "no"), ("ytdl", "no"), ("input-default-bindings", "no"), ("keep-open", keepOpen ? "yes" : "no"),
        ] {
            try handle.setOption(name, value)
        }
        try handle.initialize(onEvent: recorder.handler)
        return handle
    }

    @Test func reportsAnLGPLBuild() throws {
        let recorder = EventRecorder()
        let handle = try Self.makeHandle(videoOutput: "null", keepOpen: false, recorder: recorder)
        defer { try? handle.destroy() }
        let configuration = try #require(handle.propertyString("mpv-configuration"))
        #expect(configuration.contains("-Dgpl=false"))
    }

    @Test func playsVideoWithSeparateAudioToTheEnd() async throws {
        let recorder = EventRecorder()
        let handle = try Self.makeHandle(videoOutput: "null", keepOpen: false, recorder: recorder)
        defer { try? handle.destroy() }
        try handle.observe("time-pos", format: .double)
        try handle.observe("track-list/count", format: .int64)

        let clip = try Media.clip()
        let audio = clip.audio.path
        try handle.command(["loadfile", clip.video.path, "replace", "-1", "audio-files-append=%\(audio.utf8.count)%\(audio)"])

        #expect(try await recorder.wait { $0.contains(.fileLoaded) })
        #expect(try await recorder.wait { $0.contains(.propertyChange(id: 0, name: "track-list/count", value: .int64(2))) })
        #expect(try await recorder.wait { $0.contains(.endFile(.endOfFile)) })
        #expect((EventRecorder.lastDouble("time-pos", in: recorder.all) ?? 0) > 2.5)
    }

    @Test func pausesAndSeeks() async throws {
        let recorder = EventRecorder()
        let handle = try Self.makeHandle(videoOutput: "null", keepOpen: true, recorder: recorder)
        defer { try? handle.destroy() }
        try handle.observe("pause", format: .flag)
        try handle.observe("time-pos", format: .double)
        try handle.command(["loadfile", try Media.clip().video.path])
        #expect(try await recorder.wait { $0.contains(.playbackRestart) })

        try handle.setProperty("pause", "yes", replyID: 7)
        #expect(try await recorder.wait { $0.contains(.setPropertyReply(id: 7, error: 0)) })
        #expect(try await recorder.wait { $0.contains(.propertyChange(id: 0, name: "pause", value: .flag(true))) })

        try handle.command(["seek", "2", "absolute"], replyID: 8)
        #expect(try await recorder.wait { $0.contains(.commandReply(id: 8, error: 0)) })
        #expect(try await recorder.wait { (EventRecorder.lastDouble("time-pos", in: $0) ?? 0) >= 1.9 })
    }

    @Test func refusesASecondDestroy() throws {
        let handle = try Self.makeHandle(videoOutput: "null", keepOpen: false, recorder: EventRecorder())
        try handle.destroy()
        #expect(throws: MPVLifecycleError.alreadyDestroyed) { try handle.destroy() }
    }
}
