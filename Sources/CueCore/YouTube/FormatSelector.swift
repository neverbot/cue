import CoreMedia
import Foundation
import VideoToolbox

public struct FormatSelection: Sendable, Equatable {
    public enum Decoding: Sendable, Equatable {
        case hardware
        case software
    }

    public let video: StreamFormat
    public let audio: StreamFormat
    /// Whether the selected video is expected to decode in hardware.
    public let decoding: Decoding
}

/// Picks a video stream and an audio stream, preferring hardware decoding and falling back to software decoding
/// only when nothing hardware-friendly is on offer.
/// Hardware tier, in preference order: AV1 (only where hardware-decodable), H.264 (every Mac), VP9 (only where
/// hardware-decodable); H.264 is preferred over VP9 at an equal short side, since VP9 hardware decoding is less
/// broadly available. Software tier (used only when no offered video qualifies for the hardware tier, and only when
/// allowed): VP9 capped at 1080p, then AV1 capped at 720p — H.264 never appears here, since it is always hardware.
/// The cap applies to the short side, so portrait videos keep their quality.
/// Audio is chosen by language first: on a video with dubs, the track YouTube marks as its default wins before codec
/// and bitrate are looked at. Videos with a single soundtrack declare no language at all and are unaffected.
/// 10-bit (HDR) streams are skipped unless allowed, because tone mapping them for SDR displays costs extra GPU work.
public struct FormatSelector: Sendable {
    public var maxShortSide: Int
    public var av1HardwareDecoding: Bool
    public var allowsHighBitDepth: Bool
    public var vp9HardwareDecoding: Bool
    public var allowsSoftwareDecoding: Bool

    public init(
        maxShortSide: Int = 1080,
        av1HardwareDecoding: Bool = FormatSelector.systemSupportsAV1HardwareDecoding,
        allowsHighBitDepth: Bool = false,
        vp9HardwareDecoding: Bool = FormatSelector.systemSupportsVP9HardwareDecoding,
        allowsSoftwareDecoding: Bool = true
    ) {
        self.maxShortSide = maxShortSide
        self.av1HardwareDecoding = av1HardwareDecoding
        self.allowsHighBitDepth = allowsHighBitDepth
        self.vp9HardwareDecoding = vp9HardwareDecoding
        self.allowsSoftwareDecoding = allowsSoftwareDecoding
    }

    public static var systemSupportsAV1HardwareDecoding: Bool {
        VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
    }

    /// Registers VideoToolbox's supplemental VP9 decoder (Apple Silicon) and reports whether VP9 decodes in hardware.
    public static var systemSupportsVP9HardwareDecoding: Bool {
        VTRegisterSupplementalVideoDecoderIfAvailable(kCMVideoCodecType_VP9)
        return VTIsHardwareDecodeSupported(kCMVideoCodecType_VP9)
    }

    private enum Tier {
        case hardware
        case software
    }

    private static let audioCodecs = ["mp4a", "opus"]

    /// The formats `select(from:)` would choose among: audio it accepts, plus video from the hardware tier when any
    /// offered video qualifies there, otherwise from the software tier (if allowed). URLs are ignored.
    public func acceptableFormats(from formats: [StreamFormat]) -> [StreamFormat] {
        let audio = formats.filter { $0.kind == .audio && Self.audioCodecs.contains($0.codec) }
        guard let tier = tier(for: formats) else { return audio }
        let video = formats.filter { isAcceptableVideo($0, tier: tier) }
        return video + audio
    }

    /// The audio languages a video offers, each paired with the stream Cue would play it from — chosen inside one
    /// language by the same codec and bitrate rule `select(from:)` uses.
    ///
    /// Empty for a video with a single soundtrack, which declares no language at all: there is nothing to choose
    /// between. Every option comes from the formats handed in, so passing the resolved set (challenges already
    /// solved) yields URLs that play, and all of them come from one `/player` response.
    public func audioTrackOptions(from formats: [StreamFormat]) -> [AudioTrackOption] {
        var best: [String: StreamFormat] = [:]
        /// YouTube's own order, kept rather than sorted: it lists the original first.
        var order: [String] = []
        for format in formats where format.kind == .audio && Self.audioCodecs.contains(format.codec) {
            guard let track = format.audioTrack else { continue }
            guard let current = best[track.id] else {
                best[track.id] = format
                order.append(track.id)
                continue
            }
            if audioRank(current) < audioRank(format) { best[track.id] = format }
        }
        return order.compactMap { id in
            guard let format = best[id], let track = format.audioTrack else { return nil }
            return AudioTrackOption(track: track, url: format.url)
        }
    }

    public func select(from formats: [StreamFormat]) -> FormatSelection? {
        guard let tier = tier(for: formats) else { return nil }
        let codecs = videoCodecs(for: tier)

        let video = formats
            .filter { isAcceptableVideo($0, tier: tier) }
            .max { rank($0, codecs) < rank($1, codecs) }
        let audio = formats
            .filter { $0.kind == .audio && Self.audioCodecs.contains($0.codec) }
            .max { audioRank($0) < audioRank($1) }

        guard let video, let audio else { return nil }
        return FormatSelection(video: video, audio: audio, decoding: tier == .hardware ? .hardware : .software)
    }

    /// The tier `select(from:)` and `acceptableFormats(from:)` use: hardware when any offered video qualifies there,
    /// otherwise software (if allowed), otherwise nil.
    private func tier(for formats: [StreamFormat]) -> Tier? {
        if formats.contains(where: { isAcceptableVideo($0, tier: .hardware) }) { return .hardware }
        return allowsSoftwareDecoding ? .software : nil
    }

    private func isAcceptableVideo(_ format: StreamFormat, tier: Tier) -> Bool {
        guard format.kind == .video else { return false }
        guard videoCodecs(for: tier).contains(format.codec) else { return false }
        guard allowsHighBitDepth || (format.bitDepth ?? 8) <= 8 else { return false }
        return shortSide(format) <= maxShortSide(for: format.codec, tier: tier)
    }

    private func videoCodecs(for tier: Tier) -> [String] {
        switch tier {
        case .hardware:
            var codecs: [String] = []
            if av1HardwareDecoding { codecs.append("av01") }
            codecs.append("avc1")
            if vp9HardwareDecoding { codecs.append("vp9") }
            return codecs
        case .software:
            return ["vp9", "av01"]
        }
    }

    private func maxShortSide(for codec: String, tier: Tier) -> Int {
        switch tier {
        case .hardware:
            return maxShortSide
        case .software:
            return codec == "vp9" ? min(maxShortSide, 1080) : min(maxShortSide, 720)
        }
    }

    /// Language first, then the codec and bitrate rule that has always chosen the audio.
    ///
    /// A dubbed video offers one set of audio formats per language, and the dubs are often encoded at a higher
    /// bitrate than the original. Ranking on codec and bitrate alone therefore handed a video to whichever language
    /// happened to be encoded loudest, which is how a video opened in a language nobody asked for. The track YouTube
    /// marks as its default — the original soundtrack — outranks all of that.
    ///
    /// A video with one soundtrack carries no `audioTrack` block at all, so every format scores 0 here and the
    /// remaining two keys decide exactly as they did before. So does a dubbed video that marks no default.
    private func audioRank(_ format: StreamFormat) -> (Int, Int, Int) {
        (format.audioTrack?.isDefault == true ? 1 : 0, preference(format.codec, Self.audioCodecs), format.bitrate)
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
