import CueCore
import Foundation

/// Everything the controls need to know about a video's chapters. A value type: the window rebuilds one whenever the
/// stream changes, and every question it answers is a pure function of the list.
public struct ChapterTimeline: Equatable, Sendable {
    /// How far into a chapter "previous" still means "restart this one" rather than "go to the one before".
    public static let restartThreshold = 3.0

    public let chapters: [Chapter]
    public let duration: Double?
    /// The stream this timeline was built from, so a view can tell when to rebuild it.
    public private(set) var streamReference: PlayableStream?

    public init(chapters: [Chapter], duration: Double?) {
        self.chapters = chapters
        self.duration = duration
    }

    /// Built from a stream, which is where the window gets it.
    public init(stream: PlayableStream?) {
        self.init(chapters: stream?.chapters ?? [], duration: stream?.duration)
        streamReference = stream
    }

    public var isEmpty: Bool { chapters.isEmpty }

    public func chapter(at position: Double) -> Chapter? {
        chapters.last { position >= $0.start }
    }

    public func index(at position: Double) -> Int? {
        chapters.lastIndex { position >= $0.start }
    }

    /// Where ⌥→ goes, or nil in the last chapter.
    public func nextStart(from position: Double) -> Double? {
        chapters.first { $0.start > position }?.start
    }

    /// Where ⌥← goes: the current chapter's start when well into it, the previous chapter's otherwise, nil at the
    /// very beginning.
    public func previousStart(from position: Double) -> Double? {
        guard let index = index(at: position) else { return nil }
        let current = chapters[index]
        if position - current.start > Self.restartThreshold, current.start > 0 { return current.start }
        if position - current.start > Self.restartThreshold { return nil }
        return index > 0 ? chapters[index - 1].start : nil
    }

    /// Where to draw a tick on the seek bar, as fractions of the duration. The chapter starting at zero gets none:
    /// it is the start of the bar.
    public var tickFractions: [Double] {
        guard let duration, duration > 0 else { return [] }
        return chapters.map(\.start).filter { $0 > 0 && $0 < duration }.map { $0 / duration }
    }
}
