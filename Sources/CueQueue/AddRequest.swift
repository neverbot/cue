import CueCore
import Foundation

/// Why an add attempt was refused. Every case carries a message the app shows: a link that does nothing without
/// saying why is worse than an error.
public enum AddRequestError: Error, Equatable, Sendable {
    case notACueLink(String)
    case missingURLParameter
    case notAYouTubeVideo(String)
    case noVideoFound
}

extension AddRequestError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .notACueLink(text): "\"\(text)\" is not a Cue link. Cue links look like cue://add?url=…"
        case .missingURLParameter: "That Cue link has no url parameter, so there is nothing to add."
        case let .notAYouTubeVideo(text): "\"\(text)\" is not a YouTube video link."
        case .noVideoFound: "No YouTube video link was found."
        }
    }
}

/// Turns outside input into video ids: the `cue://add?url=…` scheme, pasted text and dropped items.
public enum AddRequest {
    public static let scheme = "cue"
    public static let addHost = "add"

    /// The link a bookmarklet or another app opens: `cue://add?url=<video URL or id>`.
    public static func url(adding videoID: VideoID) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = addHost
        components.queryItems = [URLQueryItem(name: "url", value: watchURL(for: videoID).absoluteString)]
        // The components above always form a valid URL.
        return components.url!
    }

    /// The canonical watch URL for a video id.
    public static func watchURL(for videoID: VideoID) -> URL {
        watchURL(forStoredIdentifier: videoID.rawValue)
    }

    /// The watch URL for an identifier already stored in the database. Exporting uses this so a row written by a
    /// newer version, whose id this build cannot validate, is still written out instead of silently disappearing.
    /// `URLComponents` escapes the value, so the result is a valid URL whatever the stored text is.
    public static func watchURL(forStoredIdentifier identifier: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/watch"
        components.queryItems = [URLQueryItem(name: "v", value: identifier)]
        // Scheme, host and path are fixed and the query is escaped, so this always forms a URL.
        return components.url!
    }

    /// The link for several videos at once: `cue://add?url=…&url=…`. What the browser extension sends when it is
    /// asked to hand over every YouTube tab.
    public static func url(adding videoIDs: [VideoID]) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = addHost
        components.queryItems = videoIDs.map {
            URLQueryItem(name: "url", value: watchURL(for: $0).absoluteString)
        }
        // The components above always form a valid URL; an empty list makes a bare `cue://add`, which the parser
        // then refuses for having nothing to add, exactly as it refuses one typed by hand.
        return components.url!
    }

    /// Parses a `cue://add?url=…` link. Throws, with a message to show, for anything else.
    ///
    /// The link may carry the parameter more than once, so a browser handing over twenty tabs opens one link
    /// rather than twenty: twenty would be twenty trips through Launch Services, twenty chances for the system to
    /// ask whether Cue may be opened, and twenty windows coming to the front.
    ///
    /// A link whose parameters are all unusable throws, naming the first one, because a link that silently does
    /// nothing is the failure this whole type exists to avoid. A link where *some* parse is not an error: the
    /// usable ones are added and the rest ignored, since an alert about one dead tab out of twenty would interrupt
    /// a batch that mostly worked.
    public static func videoIDs(from url: URL) throws -> [VideoID] {
        guard url.scheme?.lowercased() == scheme, url.host()?.lowercased() == addHost else {
            throw AddRequestError.notACueLink(url.absoluteString)
        }
        let values = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .filter { $0.name == "url" }
            .compactMap(\.value)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let first = values.first else {
            throw AddRequestError.missingURLParameter
        }
        var found: [VideoID] = []
        var seen: Set<VideoID> = []
        for value in values {
            guard let videoID = VideoID(url: value), seen.insert(videoID).inserted else { continue }
            found.append(videoID)
        }
        guard !found.isEmpty else {
            throw AddRequestError.notAYouTubeVideo(first)
        }
        return found
    }

    /// The first video in a `cue://add` link. Kept for callers that mean exactly one.
    public static func videoID(from url: URL) throws -> VideoID {
        // `videoIDs(from:)` never returns an empty array: it throws instead.
        try videoIDs(from: url)[0]
    }

    /// Every video id in a block of text, in order and without repeats: pasting one link or fifty, or dropping text
    /// from a browser. Lines that are not YouTube videos are ignored here; callers that must report them (import)
    /// use `QueueImport` instead.
    public static func videoIDs(in text: String) -> [VideoID] {
        var found: [VideoID] = []
        var seen: Set<VideoID> = []
        for field in text.split(whereSeparator: { $0.isNewline || $0 == " " || $0 == "\t" }) {
            guard let videoID = VideoID(url: String(field)), seen.insert(videoID).inserted else { continue }
            found.append(videoID)
        }
        return found
    }

    /// The ids in dropped or pasted items: file URLs are ignored, everything else is read as text.
    public static func videoIDs(inDropped items: [String]) -> [VideoID] {
        videoIDs(in: items.joined(separator: "\n"))
    }
}
