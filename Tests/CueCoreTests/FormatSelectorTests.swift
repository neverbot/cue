import Foundation
import Testing
@testable import CueCore

@Suite struct FormatSelectorTests {
    func stream(_ itag: Int, _ kind: StreamFormat.Kind, _ codec: String, width: Int? = nil, height: Int? = nil, bitrate: Int) -> StreamFormat {
        StreamFormat(
            itag: itag, kind: kind, container: codec == "opus" || codec == "vp9" ? "webm" : "mp4", codec: codec,
            bitrate: bitrate, width: width, height: height, fps: 30,
            url: URL(string: "https://rr1.googlevideo.com/videoplayback?itag=\(itag)")!,
            nChallenge: nil, signatureChallenge: nil
        )
    }

    var catalogue: [StreamFormat] {
        [
            stream(401, .video, "av01", height: 2160, bitrate: 20_000_000),
            stream(399, .video, "av01", height: 1080, bitrate: 3_000_000),
            stream(137, .video, "avc1", height: 1080, bitrate: 4_000_000),
            stream(248, .video, "vp9", height: 1080, bitrate: 2_500_000),
            stream(136, .video, "avc1", height: 720, bitrate: 2_000_000),
            stream(140, .audio, "mp4a", bitrate: 130_000),
            stream(251, .audio, "opus", bitrate: 160_000),
        ]
    }

    @Test func prefersH264WithoutAV1Hardware() throws {
        let selection = try #require(FormatSelector(maxHeight: 1080, av1HardwareDecoding: false).select(from: catalogue))
        #expect(selection.video.itag == 137)
        #expect(selection.audio.itag == 140)
    }

    @Test func prefersAV1WithHardwareAtSameHeight() throws {
        let selection = try #require(FormatSelector(maxHeight: 1080, av1HardwareDecoding: true).select(from: catalogue))
        #expect(selection.video.itag == 399)
    }

    @Test func respectsMaxHeight() throws {
        let selection = try #require(FormatSelector(maxHeight: 720, av1HardwareDecoding: false).select(from: catalogue))
        #expect(selection.video.itag == 136)
    }

    @Test func fallsBackToOpusWhenNoAAC() throws {
        let withoutAAC = catalogue.filter { $0.itag != 140 }
        let selection = try #require(FormatSelector(maxHeight: 1080, av1HardwareDecoding: false).select(from: withoutAAC))
        #expect(selection.audio.itag == 251)
    }

    @Test func returnsNilWithoutUsableStreams() {
        let audioOnly = catalogue.filter { $0.kind == .audio }
        #expect(FormatSelector(maxHeight: 1080, av1HardwareDecoding: false).select(from: audioOnly) == nil)
    }

    @Test func capsPortraitVideosByShortSide() throws {
        let portrait = [
            stream(137, .video, "avc1", width: 1080, height: 1920, bitrate: 4_000_000),
            stream(136, .video, "avc1", width: 720, height: 1280, bitrate: 2_000_000),
            stream(135, .video, "avc1", width: 480, height: 854, bitrate: 1_000_000),
            stream(140, .audio, "mp4a", bitrate: 130_000),
        ]
        let selection = try #require(FormatSelector(maxHeight: 1080, av1HardwareDecoding: false).select(from: portrait))
        #expect(selection.video.itag == 137)
    }

    @Test func keepsPortraitVideoWithOnlyTheTopRung() throws {
        let portrait = [
            stream(137, .video, "avc1", width: 1080, height: 1920, bitrate: 4_000_000),
            stream(140, .audio, "mp4a", bitrate: 130_000),
        ]
        let selection = try #require(FormatSelector(maxHeight: 1080, av1HardwareDecoding: false).select(from: portrait))
        #expect(selection.video.itag == 137)
    }

    @Test func neverSelectsCodecsWithoutReliableHardwareDecoding() throws {
        let formats = [
            stream(248, .video, "vp9", width: 1920, height: 1080, bitrate: 9_000_000),
            stream(136, .video, "avc1", width: 1280, height: 720, bitrate: 2_000_000),
            stream(140, .audio, "mp4a", bitrate: 130_000),
        ]
        let selection = try #require(FormatSelector(maxHeight: 1080, av1HardwareDecoding: false).select(from: formats))
        #expect(selection.video.itag == 136)
    }
}
