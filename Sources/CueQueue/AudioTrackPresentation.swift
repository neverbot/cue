import CueCore
import CuePlayer
import Foundation

/// One row on the inspector's audio page, ready to draw. The view layer adds no logic of its own.
public struct AudioTrackRow: Equatable, Sendable {
    /// YouTube's own track id, which is what a selection is reported back as.
    public var id: String
    public var title: String
    public var isSelected: Bool

    public init(id: String, title: String, isSelected: Bool) {
        self.id = id
        self.title = title
        self.isSelected = isSelected
    }
}

/// What the audio page lists and which row it marks. Pure functions, so the page's behaviour is decided somewhere
/// that is tested: `Sources/Cue` has no automated coverage by design.
public enum AudioTrackPresentation {
    /// Said instead of a list when the video has one soundtrack. A list of one offers a choice that does not exist,
    /// and a blank column reads as a broken one — the chapters page states its emptiness in words for the same
    /// reason, and in the same voice.
    public static let singleTrackMessage = "This video has one audio track."

    /// The rows, in the order YouTube listed the languages, and empty whenever there is nothing to choose between —
    /// so a video with one track (or none) shows `singleTrackMessage` rather than a one-row list.
    public static func rows(for tracks: [AudioTrackOption], selected: String?) -> [AudioTrackRow] {
        guard tracks.count > 1 else { return [] }
        return tracks.map { AudioTrackRow(id: $0.id, title: $0.menuTitle, isSelected: $0.id == selected) }
    }

    /// The row to mark as playing, or nil when none of the listed tracks is.
    public static func selectedRow(in rows: [AudioTrackRow]) -> Int? {
        rows.firstIndex { $0.isSelected }
    }
}
