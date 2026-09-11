import CoreMedia
import Foundation
import VideoToolbox

public struct FormatSelection: Sendable, Equatable {
    public let video: StreamFormat
    public let audio: StreamFormat
}

/// Picks a hardware-decodable video stream and an audio stream.
/// H.264 is decoded in hardware on every Mac; AV1 only on chips that support it; VP9 is avoided (software decode).
public struct FormatSelector: Sendable {
    public var maxHeight: Int
    public var av1HardwareDecoding: Bool

    public init(maxHeight: Int = 1080, av1HardwareDecoding: Bool = FormatSelector.systemSupportsAV1HardwareDecoding) {
        self.maxHeight = maxHeight
        self.av1HardwareDecoding = av1HardwareDecoding
    }

    public static var systemSupportsAV1HardwareDecoding: Bool {
        VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
    }

    public func select(from formats: [StreamFormat]) -> FormatSelection? {
        let videoCodecs = av1HardwareDecoding ? ["av01", "avc1"] : ["avc1"]
        let audioCodecs = ["mp4a", "opus"]

        let video = formats
            .filter { $0.kind == .video && videoCodecs.contains($0.codec) && ($0.height ?? 0) <= maxHeight }
            .max { rank($0, videoCodecs) < rank($1, videoCodecs) }
        let audio = formats
            .filter { $0.kind == .audio && audioCodecs.contains($0.codec) }
            .max { (preference($0.codec, audioCodecs), $0.bitrate) < (preference($1.codec, audioCodecs), $1.bitrate) }

        guard let video, let audio else { return nil }
        return FormatSelection(video: video, audio: audio)
    }

    private func rank(_ format: StreamFormat, _ codecs: [String]) -> (Int, Int, Int) {
        (format.height ?? 0, preference(format.codec, codecs), format.bitrate)
    }

    private func preference(_ codec: String, _ ordered: [String]) -> Int {
        guard let index = ordered.firstIndex(of: codec) else { return 0 }
        return ordered.count - index
    }
}
