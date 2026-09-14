import Foundation

/// One audio language a video offers.
///
/// A video with a single soundtrack carries no `audioTrack` block at all, so a nil `AudioTrack` on a `StreamFormat`
/// means "this video has one language", never "the language is unknown". Only dubbed videos describe their tracks,
/// and then every audio format carries one.
public struct AudioTrack: Sendable, Equatable, Identifiable {
    /// YouTube's own track id, `en.4` or `es-ES.3`. Stable within a video and the key a switch is made on.
    public let id: String
    /// What YouTube calls the track, in the language of the request (`hl=en`): "English original", "Spanish (Spain)".
    public let displayName: String
    /// Set on the track YouTube serves by default — the original soundtrack, not one of the dubs.
    public let isDefault: Bool

    public init(id: String, displayName: String, isDefault: Bool) {
        self.id = id
        self.displayName = displayName
        self.isDefault = isDefault
    }

    /// BCP-47 as YouTube writes it, taken from the id's first field: `en.4` is `en`, `es-ES.3` is `es-ES`.
    public var languageCode: String {
        String(id.split(separator: ".").first ?? "")
    }

    /// What a row shows. YouTube's own display name already says which track is the original, so nothing is appended
    /// to it: "English original (original)" would be the same fact twice.
    public var menuTitle: String { displayName }

    /// The block YouTube attaches to every audio format of a dubbed video. A block without an id is dropped: the id
    /// is what tells two tracks apart, and a track that cannot be told apart cannot be switched to.
    init?(raw: PlayerResponse.RawFormat.AudioTrack?) {
        guard let raw, let id = raw.id, !id.isEmpty else { return nil }
        self.id = id
        let name = raw.displayName ?? ""
        // A track with no name of its own is shown by its language code, which is the only other thing known
        // about it. An empty row would say less.
        displayName = name.isEmpty ? (id.split(separator: ".").first.map(String.init) ?? id) : name
        isDefault = raw.audioIsDefault ?? false
    }
}

/// One audio track together with the stream that plays it.
///
/// Every dubbed track comes from the same `/player` response, so all of these are known the moment a video is
/// resolved: switching between them costs no request and no re-resolve.
///
/// The URL is a signed stream URL with the requester's address inside it. It is never logged, never shown and never
/// marked public in a log message, exactly like the URLs in `StreamFormat`.
public struct AudioTrackOption: Sendable, Equatable, Identifiable {
    public let track: AudioTrack
    public let url: URL

    public init(track: AudioTrack, url: URL) {
        self.track = track
        self.url = url
    }

    public var id: String { track.id }
    public var menuTitle: String { track.menuTitle }
    public var isDefault: Bool { track.isDefault }
}
