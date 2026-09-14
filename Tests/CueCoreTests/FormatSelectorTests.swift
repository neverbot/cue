import Foundation
import Testing
@testable import CueCore

@Suite struct FormatSelectorTests {
    func stream(
        _ itag: Int, _ kind: StreamFormat.Kind, _ codec: String, width: Int? = nil, height: Int? = nil,
        bitDepth: Int? = nil, audioTrack: AudioTrack? = nil, bitrate: Int
    ) -> StreamFormat {
        StreamFormat(
            itag: itag, kind: kind, container: codec == "opus" || codec == "vp9" ? "webm" : "mp4", codec: codec, bitDepth: bitDepth,
            bitrate: bitrate, width: width, height: height, fps: 30,
            url: URL(string: "https://rr1.googlevideo.com/videoplayback?itag=\(itag)")!,
            nChallenge: nil, signatureChallenge: nil, audioTrack: audioTrack
        )
    }

    /// The original soundtrack, as YouTube marks it.
    static let original = AudioTrack(id: "en.4", displayName: "English original", isDefault: true)
    /// A dub, as YouTube marks it: same shape, no default flag.
    static let dub = AudioTrack(id: "es-ES.3", displayName: "Spanish (Spain)", isDefault: false)

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
        let selection = try #require(FormatSelector(maxShortSide: 1080, av1HardwareDecoding: false, vp9HardwareDecoding: false).select(from: catalogue))
        #expect(selection.video.itag == 137)
        #expect(selection.audio.itag == 140)
    }

    @Test func prefersAV1WithHardwareAtSameHeight() throws {
        let selection = try #require(FormatSelector(maxShortSide: 1080, av1HardwareDecoding: true, vp9HardwareDecoding: false).select(from: catalogue))
        #expect(selection.video.itag == 399)
    }

    @Test func respectsMaxHeight() throws {
        let selection = try #require(FormatSelector(maxShortSide: 720, av1HardwareDecoding: false, vp9HardwareDecoding: false).select(from: catalogue))
        #expect(selection.video.itag == 136)
    }

    @Test func fallsBackToOpusWhenNoAAC() throws {
        let withoutAAC = catalogue.filter { $0.itag != 140 }
        let selection = try #require(FormatSelector(maxShortSide: 1080, av1HardwareDecoding: false, vp9HardwareDecoding: false).select(from: withoutAAC))
        #expect(selection.audio.itag == 251)
    }

    @Test func returnsNilWithoutUsableStreams() {
        let audioOnly = catalogue.filter { $0.kind == .audio }
        #expect(FormatSelector(maxShortSide: 1080, av1HardwareDecoding: false, vp9HardwareDecoding: false).select(from: audioOnly) == nil)
    }

    @Test func capsPortraitVideosByShortSide() throws {
        let portrait = [
            stream(137, .video, "avc1", width: 1080, height: 1920, bitrate: 4_000_000),
            stream(136, .video, "avc1", width: 720, height: 1280, bitrate: 2_000_000),
            stream(135, .video, "avc1", width: 480, height: 854, bitrate: 1_000_000),
            stream(140, .audio, "mp4a", bitrate: 130_000),
        ]
        let selection = try #require(FormatSelector(maxShortSide: 1080, av1HardwareDecoding: false, vp9HardwareDecoding: false).select(from: portrait))
        #expect(selection.video.itag == 137)
    }

    @Test func keepsPortraitVideoWithOnlyTheTopRung() throws {
        let portrait = [
            stream(137, .video, "avc1", width: 1080, height: 1920, bitrate: 4_000_000),
            stream(140, .audio, "mp4a", bitrate: 130_000),
        ]
        let selection = try #require(FormatSelector(maxShortSide: 1080, av1HardwareDecoding: false, vp9HardwareDecoding: false).select(from: portrait))
        #expect(selection.video.itag == 137)
    }

    @Test func neverSelectsCodecsWithoutReliableHardwareDecoding() throws {
        let formats = [
            stream(248, .video, "vp9", width: 1920, height: 1080, bitrate: 9_000_000),
            stream(136, .video, "avc1", width: 1280, height: 720, bitrate: 2_000_000),
            stream(140, .audio, "mp4a", bitrate: 130_000),
        ]
        let selection = try #require(FormatSelector(maxShortSide: 1080, av1HardwareDecoding: false, vp9HardwareDecoding: false).select(from: formats))
        #expect(selection.video.itag == 136)
    }

    @Test func prefersSDRAV1OverHDR() throws {
        let formats = [
            stream(399, .video, "av01", width: 1920, height: 1080, bitDepth: 8, bitrate: 1_600_000),
            stream(699, .video, "av01", width: 1920, height: 1080, bitDepth: 10, bitrate: 5_000_000),
            stream(137, .video, "avc1", width: 1920, height: 1080, bitrate: 4_000_000),
            stream(140, .audio, "mp4a", bitrate: 130_000),
        ]
        let selection = try #require(FormatSelector(maxShortSide: 1080, av1HardwareDecoding: true, vp9HardwareDecoding: false).select(from: formats))
        #expect(selection.video.itag == 399)
    }

    @Test func selectsHDRWhenAllowed() throws {
        let formats = [
            stream(399, .video, "av01", width: 1920, height: 1080, bitDepth: 8, bitrate: 1_600_000),
            stream(699, .video, "av01", width: 1920, height: 1080, bitDepth: 10, bitrate: 5_000_000),
            stream(137, .video, "avc1", width: 1920, height: 1080, bitrate: 4_000_000),
            stream(140, .audio, "mp4a", bitrate: 130_000),
        ]
        let selection = try #require(
            FormatSelector(maxShortSide: 1080, av1HardwareDecoding: true, allowsHighBitDepth: true, vp9HardwareDecoding: false).select(from: formats)
        )
        #expect(selection.video.itag == 699)
    }

    @Test func acceptableFormatsReturnsHardwareTierWhenHardwareVideoIsOffered() throws {
        let selector = FormatSelector(maxShortSide: 1080, av1HardwareDecoding: false, vp9HardwareDecoding: false)
        let formats = [
            stream(137, .video, "avc1", width: 1920, height: 1080, bitrate: 4_000_000),
            stream(248, .video, "vp9", width: 1920, height: 1080, bitrate: 2_500_000),
            stream(401, .video, "avc1", width: 3840, height: 2160, bitrate: 20_000_000),
            stream(399, .video, "av01", width: 1920, height: 1080, bitrate: 3_000_000),
            stream(140, .audio, "mp4a", bitrate: 130_000),
            stream(251, .audio, "opus", bitrate: 160_000),
        ]
        let acceptable = selector.acceptableFormats(from: formats)
        #expect(Set(acceptable.map(\.itag)) == [137, 140, 251])
    }

    @Test func acceptableFormatsFallsBackToSoftwareTierWhenNoHardwareVideoIsOffered() throws {
        let selector = FormatSelector(maxShortSide: 2160, av1HardwareDecoding: false, vp9HardwareDecoding: false)
        let formats = [
            stream(313, .video, "vp9", width: 3840, height: 2160, bitrate: 12_000_000),
            stream(248, .video, "vp9", width: 1920, height: 1080, bitrate: 2_500_000),
            stream(399, .video, "av01", width: 1280, height: 720, bitrate: 1_500_000),
            stream(140, .audio, "mp4a", bitrate: 130_000),
        ]
        let acceptable = selector.acceptableFormats(from: formats)
        #expect(Set(acceptable.map(\.itag)) == [248, 399, 140])
    }

    @Test func fallsBackToH264WhenAV1IsOnlyHDR() throws {
        let formats = [
            stream(699, .video, "av01", width: 1920, height: 1080, bitDepth: 10, bitrate: 5_000_000),
            stream(137, .video, "avc1", width: 1920, height: 1080, bitrate: 4_000_000),
            stream(140, .audio, "mp4a", bitrate: 130_000),
        ]
        let selection = try #require(FormatSelector(maxShortSide: 1080, av1HardwareDecoding: true, vp9HardwareDecoding: false).select(from: formats))
        #expect(selection.video.itag == 137)
    }

    @Test func selectsHardwareVP9WhenItHasTheBestShortSide() throws {
        let formats = [
            stream(271, .video, "vp9", width: 2560, height: 1440, bitrate: 8_000_000),
            stream(137, .video, "avc1", width: 1920, height: 1080, bitrate: 4_000_000),
            stream(140, .audio, "mp4a", bitrate: 130_000),
        ]
        let selection = try #require(
            FormatSelector(maxShortSide: 1440, av1HardwareDecoding: false, vp9HardwareDecoding: true).select(from: formats)
        )
        #expect(selection.video.itag == 271)
        #expect(selection.decoding == .hardware)
    }

    @Test func prefersH264OverHardwareVP9AtTheSameShortSide() throws {
        let formats = [
            stream(248, .video, "vp9", width: 1920, height: 1080, bitrate: 9_000_000),
            stream(137, .video, "avc1", width: 1920, height: 1080, bitrate: 4_000_000),
            stream(140, .audio, "mp4a", bitrate: 130_000),
        ]
        let selection = try #require(
            FormatSelector(maxShortSide: 1080, av1HardwareDecoding: false, vp9HardwareDecoding: true).select(from: formats)
        )
        #expect(selection.video.itag == 137)
    }

    @Test func fallsBackToSoftwareVP9CappedAt1080() throws {
        let formats = [
            stream(313, .video, "vp9", width: 3840, height: 2160, bitrate: 12_000_000),
            stream(248, .video, "vp9", width: 1920, height: 1080, bitrate: 2_500_000),
            stream(140, .audio, "mp4a", bitrate: 130_000),
        ]
        let selection = try #require(
            FormatSelector(maxShortSide: 2160, av1HardwareDecoding: false, vp9HardwareDecoding: false).select(from: formats)
        )
        #expect(selection.video.itag == 248)
        #expect(selection.decoding == .software)
    }

    @Test func fallsBackToSoftwareAV1CappedAt720WhenNoVP9() throws {
        let formats = [
            stream(399, .video, "av01", width: 1920, height: 1080, bitrate: 3_000_000),
            stream(398, .video, "av01", width: 1280, height: 720, bitrate: 1_500_000),
            stream(140, .audio, "mp4a", bitrate: 130_000),
        ]
        let selection = try #require(
            FormatSelector(maxShortSide: 1080, av1HardwareDecoding: false, vp9HardwareDecoding: false).select(from: formats)
        )
        #expect(selection.video.itag == 398)
        #expect(selection.decoding == .software)
    }

    @Test func returnsNilWithoutHardwareStreamsWhenSoftwareIsDisallowed() throws {
        let formats = [
            stream(248, .video, "vp9", width: 1920, height: 1080, bitrate: 2_500_000),
            stream(140, .audio, "mp4a", bitrate: 130_000),
        ]
        #expect(
            FormatSelector(maxShortSide: 1080, av1HardwareDecoding: false, vp9HardwareDecoding: false, allowsSoftwareDecoding: false)
                .select(from: formats) == nil
        )
    }

    /// The reported failure. YouTube encodes dubs at least as generously as the original, so ranking audio on codec
    /// and bitrate alone opened a dubbed video in whichever language happened to be loudest.
    @Test func prefersTheDefaultTrackOverALouderDub() throws {
        let formats = [
            stream(137, .video, "avc1", width: 1920, height: 1080, bitrate: 4_000_000),
            stream(140, .audio, "mp4a", audioTrack: Self.original, bitrate: 130_000),
            stream(141, .audio, "mp4a", audioTrack: Self.dub, bitrate: 190_000),
        ]
        let selection = try #require(FormatSelector(maxShortSide: 1080, av1HardwareDecoding: false, vp9HardwareDecoding: false).select(from: formats))
        #expect(selection.audio.audioTrack?.id == "en.4")
        #expect(selection.audio.itag == 140)
    }

    /// Language outranks the codec too: a default track is the one the video is meant to be heard in, whichever
    /// container it arrived in.
    @Test func prefersTheDefaultTrackAcrossCodecs() throws {
        let formats = [
            stream(137, .video, "avc1", width: 1920, height: 1080, bitrate: 4_000_000),
            stream(251, .audio, "opus", audioTrack: Self.original, bitrate: 160_000),
            stream(140, .audio, "mp4a", audioTrack: Self.dub, bitrate: 190_000),
        ]
        let selection = try #require(FormatSelector(maxShortSide: 1080, av1HardwareDecoding: false, vp9HardwareDecoding: false).select(from: formats))
        #expect(selection.audio.audioTrack?.id == "en.4")
        #expect(selection.audio.codec == "opus")
    }

    /// A dubbed video that marks no default at all leaves the old rule in charge rather than picking arbitrarily.
    @Test func fallsBackToCodecAndBitrateWhenNoTrackIsMarkedDefault() throws {
        let quiet = AudioTrack(id: "en.4", displayName: "English", isDefault: false)
        let formats = [
            stream(137, .video, "avc1", width: 1920, height: 1080, bitrate: 4_000_000),
            stream(140, .audio, "mp4a", audioTrack: quiet, bitrate: 130_000),
            stream(141, .audio, "mp4a", audioTrack: Self.dub, bitrate: 190_000),
        ]
        let selection = try #require(FormatSelector(maxShortSide: 1080, av1HardwareDecoding: false, vp9HardwareDecoding: false).select(from: formats))
        #expect(selection.audio.audioTrack?.id == "es-ES.3")
        #expect(selection.audio.bitrate == 190_000)
    }

    /// A video with one soundtrack sends no `audioTrack` block on anything, and must be chosen exactly as it was
    /// before languages were modelled at all: AAC ahead of Opus, on bitrate.
    @Test func leavesSingleLanguageVideosAsTheyWere() throws {
        let selection = try #require(FormatSelector(maxShortSide: 1080, av1HardwareDecoding: false, vp9HardwareDecoding: false).select(from: catalogue))
        #expect(selection.audio.itag == 140)
        #expect(selection.audio.audioTrack == nil)
    }

    @Test func hardwareSelectionsReportHardware() throws {
        let selection = try #require(FormatSelector(maxShortSide: 1080, av1HardwareDecoding: false, vp9HardwareDecoding: false).select(from: catalogue))
        #expect(selection.decoding == .hardware)
    }
}
