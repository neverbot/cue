import Foundation

/// One section of a video, as the video itself describes it. Cue never invents chapters and never asks anyone else
/// for them: they come from the video's own markers or from the timestamps in its description.
public struct Chapter: Equatable, Sendable, Identifiable {
    public let title: String
    public let start: Double
    /// Where the next chapter begins, or the end of the video. Nil only when the duration is unknown for the last one.
    public let end: Double?

    public init(title: String, start: Double, end: Double? = nil) {
        self.title = title
        self.start = start
        self.end = end
    }

    public var id: Double { start }

    public func contains(_ position: Double) -> Bool {
        position >= start && (end.map { position < $0 } ?? true)
    }

    /// Closes an ordered list of open-ended chapters: each ends where the next starts, the last at the duration.
    /// Chapters that start at or past the duration are dropped, as are ones that go backwards.
    static func closing(_ chapters: [Chapter], duration: Double?) -> [Chapter] {
        var kept: [Chapter] = []
        for chapter in chapters {
            guard chapter.start >= 0 else { continue }
            if let duration, chapter.start >= duration { continue }
            if let last = kept.last, chapter.start <= last.start { continue }
            kept.append(chapter)
        }
        return kept.enumerated().map { index, chapter in
            Chapter(title: chapter.title, start: chapter.start, end: index + 1 < kept.count ? kept[index + 1].start : duration)
        }
    }

    /// Timestamps at the start of a description line: `0:00 Intro`, `1:02:03 The long tail`.
    ///
    /// The list is only a table of contents when it starts at zero; anything else is a description that happens to
    /// mention times, and turning that into chapters would put nonsense on the seek bar.
    public static func list(inDescription description: String, duration: Double?) -> [Chapter] {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*(?:(\d{1,2}):)?(\d{1,2}):(\d{2})\s+(\S.*?)\s*$"#) else { return [] }
        var found: [Chapter] = []
        for line in description.components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range) else { continue }
            func group(_ index: Int) -> String? {
                Range(match.range(at: index), in: line).map { String(line[$0]) }
            }
            guard let minutes = group(2).flatMap(Double.init), let seconds = group(3).flatMap(Double.init),
                  let title = group(4), !title.isEmpty
            else { continue }
            let hours = group(1).flatMap(Double.init) ?? 0
            found.append(Chapter(title: title, start: hours * 3600 + minutes * 60 + seconds))
        }
        guard found.first?.start == 0, found.count > 1 else { return [] }
        return closing(found, duration: duration)
    }
}
