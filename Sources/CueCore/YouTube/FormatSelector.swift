import CoreMedia
import Foundation
import VideoToolbox

public struct FormatSelection: Sendable, Equatable {
    public let video: StreamFormat
    public let audio: StreamFormat
}

/// Picks a hardware-decodable video stream and an audio stream.
/// H.264 is decoded in hardware on every Mac and AV1 only on chips that support it; VP9 is avoided because it is not
/// reliably hardware-decoded. The cap applies to the short side, so portrait videos keep their quality.
/// 10-bit (HDR) streams are skipped unless allowed, because tone mapping them for SDR displays costs extra GPU work.
public struct FormatSelector: Sendable {
    public var maxShortSide: Int
    public var av1HardwareDecoding: Bool
    public var allowsHighBitDepth: Bool

    public init(
        maxShortSide: Int = 1080,
        av1HardwareDecoding: Bool = FormatSelector.systemSupportsAV1HardwareDecoding,
        allowsHighBitDepth: Bool = false
    ) {
        self.maxShortSide = maxShortSide
        self.av1HardwareDecoding = av1HardwareDecoding
        self.allowsHighBitDepth = allowsHighBitDepth
    }

    public static var systemSupportsAV1HardwareDecoding: Bool {
        VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
    }

    private var videoCodecs: [String] { av1HardwareDecoding ? ["av01", "avc1"] : ["avc1"] }
    private static let audioCodecs = ["mp4a", "opus"]

    /// Whether `format` could ever be selected under this configuration (codec, bit depth and size), ignoring URLs.
    public func accepts(_ format: StreamFormat) -> Bool {
        switch format.kind {
        case .video:
            videoCodecs.contains(format.codec) && shortSide(format) <= maxShortSide && (allowsHighBitDepth || (format.bitDepth ?? 8) <= 8)
        case .audio:
            Self.audioCodecs.contains(format.codec)
        }
    }

    public func select(from formats: [StreamFormat]) -> FormatSelection? {
        let video = formats
            .filter { $0.kind == .video && accepts($0) }
            .max { rank($0, videoCodecs) < rank($1, videoCodecs) }
        let audio = formats
            .filter { $0.kind == .audio && accepts($0) }
            .max { (preference($0.codec, Self.audioCodecs), $0.bitrate) < (preference($1.codec, Self.audioCodecs), $1.bitrate) }

        guard let video, let audio else { return nil }
        return FormatSelection(video: video, audio: audio)
    }

    private func rank(_ format: StreamFormat, _ codecs: [String]) -> (Int, Int, Int) {
        (shortSide(format), preference(format.codec, codecs), format.bitrate)
    }

    /// The quality label dimension: `min(width, height)`, or `height` when the width is unknown.
    private func shortSide(_ format: StreamFormat) -> Int {
        if let width = format.width, let height = format.height { return min(width, height) }
        return format.height ?? 0
    }

    private func preference(_ codec: String, _ ordered: [String]) -> Int {
        guard let index = ordered.firstIndex(of: codec) else { return 0 }
        return ordered.count - index
    }
}
