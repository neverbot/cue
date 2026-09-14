import Foundation

/// One line of subtitle, on screen from `start` to `end`.
public struct CaptionCue: Equatable, Sendable {
    public let start: Double
    public let end: Double
    public let text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }

    public var lines: [String] { text.components(separatedBy: "\n") }
}

/// Reads YouTube's `json3` timed text. The format carries styling Cue ignores: mpv draws subtitles with the user's
/// own style (`SubtitleStyle`), and an export that promised YouTube's positioning could not keep it.
public enum TimedText {
    private struct Response: Decodable {
        struct Event: Decodable {
            struct Segment: Decodable {
                let utf8: String?
            }

            let tStartMs: Double?
            let dDurationMs: Double?
            let segs: [Segment]?
        }

        let events: [Event]?
    }

    /// Cues in order, with empty and positioning-only events dropped and overlaps trimmed.
    public static func cues(fromJSON3 data: Data) throws -> [CaptionCue] {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ExtractionError.unexpectedResponse
        }
        let events = response.events ?? []
        var cues: [CaptionCue] = []
        for (index, event) in events.enumerated() {
            guard let segments = event.segs else { continue }
            let text = segments.compactMap(\.utf8).joined()
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let start = (event.tStartMs ?? 0) / 1000
            // An event with no duration lasts until the next thing happens on screen.
            let nextStart = events[(index + 1)...].compactMap(\.tStartMs).first.map { $0 / 1000 }
            let end = event.dDurationMs.map { start + $0 / 1000 } ?? nextStart ?? start + 2
            cues.append(CaptionCue(start: start, end: max(end, start), text: text))
        }
        // Two cues on screen at once is how YouTube writes rolling transcripts; a subtitle file cannot say that, so
        // each cue stops where the next begins.
        return cues.enumerated().map { index, cue in
            guard index + 1 < cues.count else { return cue }
            return CaptionCue(start: cue.start, end: min(cue.end, cues[index + 1].start), text: cue.text)
        }
    }
}

/// What an exported subtitle file is written as.
///
/// Separate from `CaptionTrack.TimedTextFormat`, which says what Cue asks YouTube for: the two lists have no reason
/// to agree. Cue downloads `json3` and writes SubRip from it, so an export format is a property of the file the user
/// saves and nothing to do with the request that fetched the cues.
public enum ExportFormat: String, Sendable, CaseIterable {
    case srt
    case vtt

    /// The extension the saved file gets, matching the name the format is known by.
    public var fileExtension: String { rawValue }
}

/// Writes cues as SubRip or WebVTT. Both are UTF-8 text with `\n` line endings.
public enum SubtitleWriter {
    /// The file's text in the format asked for.
    public static func text(_ cues: [CaptionCue], as format: ExportFormat) -> String {
        switch format {
        case .srt: srt(cues)
        case .vtt: vtt(cues)
        }
    }

    public static func srt(_ cues: [CaptionCue]) -> String {
        format(cues, decimalSeparator: ",", header: nil)
    }

    public static func vtt(_ cues: [CaptionCue]) -> String {
        format(cues, decimalSeparator: ".", header: "WEBVTT")
    }

    /// `hh:mm:ss,mmm` or `hh:mm:ss.mmm`. Milliseconds are truncated, never rounded up past the cue's end.
    static func timestamp(_ seconds: Double, decimalSeparator: String) -> String {
        let total = seconds.isFinite ? max(0, seconds) : 0
        let milliseconds = Int((total * 1000).rounded(.down))
        return String(
            format: "%02d:%02d:%02d%@%03d",
            milliseconds / 3_600_000,
            (milliseconds % 3_600_000) / 60_000,
            (milliseconds % 60_000) / 1000,
            decimalSeparator,
            milliseconds % 1000
        )
    }

    /// A header (present only for VTT) followed by one blank-line-separated block per cue, ending in a single
    /// trailing newline. An empty track is just the header, or nothing at all for SRT.
    private static func format(_ cues: [CaptionCue], decimalSeparator: String, header: String?) -> String {
        guard !cues.isEmpty else { return header.map { "\($0)\n" } ?? "" }
        let prefix = header.map { "\($0)\n\n" } ?? ""
        let blocks = cues.enumerated().map { index, cue in
            """
            \(index + 1)
            \(timestamp(cue.start, decimalSeparator: decimalSeparator)) --> \(timestamp(cue.end, decimalSeparator: decimalSeparator))
            \(cue.text)
            """
        }
        return prefix + blocks.joined(separator: "\n\n") + "\n"
    }
}
