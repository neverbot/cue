import CueCore
import Foundation

/// Which audio language is playing, and the commands that put mpv in that state.
///
/// YouTube serves DASH audio apart from the video, so Cue already attaches the chosen language as an **external**
/// audio track when the file is loaded (`LoadRequest.arguments`). Switching language is therefore the same move
/// `SubtitleSession` makes, in the same vocabulary: remove the one external track, add the next, select it by id.
/// That is also what keeps the id predictable — `audio-add` answers asynchronously and never tells the caller which
/// id it got, but with exactly one external audio track loaded it is always the first one.
///
/// Nothing here reloads the file, and nothing here asks YouTube for anything. `audio-add` and `audio-remove` act on
/// the file that is playing, so the position and the pause state are untouched by construction; and every language
/// came from the same `/player` response, so all their URLs are already known and no re-resolve is needed.
public struct AudioTrackSession: Equatable, Sendable {
    /// The id of the only external audio track Cue ever has loaded.
    public static let externalTrackID = 1

    /// The languages this video offers, in the order YouTube listed them. Empty when it has one soundtrack.
    public private(set) var tracks: [AudioTrackOption]
    /// The one playing now.
    public private(set) var selectedID: String?

    public init(tracks: [AudioTrackOption] = [], selectedID: String? = nil) {
        self.tracks = tracks
        self.selectedID = selectedID
    }

    /// The session for a video, taken from the stream it was resolved into. A new video gets a new session: the
    /// languages are the video's, not the user's, so there is nothing to carry over.
    public init(stream: PlayableStream?) {
        self.init(tracks: stream?.audioTracks ?? [], selectedID: stream?.selectedAudioTrackID)
    }

    /// Whether there is anything to choose between. One track is not a choice.
    public var offersAChoice: Bool { tracks.count > 1 }

    public var selected: AudioTrackOption? { tracks.first { $0.id == selectedID } }

    /// Replaces the loaded external audio track with `option`'s.
    ///
    /// Nothing is sent for the track already playing: re-adding it would drop a moment of sound to arrive back where
    /// it started. A track this video does not offer is refused for the same reason — it has no stream to add.
    public mutating func select(_ option: AudioTrackOption) -> [PlayerCommand] {
        guard option.id != selectedID, tracks.contains(where: { $0.id == option.id }) else { return [] }
        selectedID = option.id
        // Removed first, exactly like a subtitle: the load already attached one external audio track, and leaving it
        // behind would stack a second language on top of the first rather than replacing it.
        return [.removeAudioTracks, .addAudioTrack(url: option.url), .selectAudioTrack(id: Self.externalTrackID)]
    }

    /// The option for a track id, or nil when this video does not offer it.
    public func option(id: String) -> AudioTrackOption? { tracks.first { $0.id == id } }
}
