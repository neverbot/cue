import CueCore
import Foundation
import GRDB

/// One queued video. The id is stored as text: a row written by a future version with an id this build rejects can
/// still be listed and deleted instead of crashing the app.
public struct QueueItem: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "queueItem"

    public var videoID: String
    public var title: String
    public var author: String?
    /// Seconds, when known.
    public var duration: Double?
    public var addedAt: Date
    /// Order in the queue; gaps are allowed between values.
    public var sortIndex: Int
    public var watchedAt: Date?

    public init(
        videoID: String,
        title: String,
        author: String? = nil,
        duration: Double? = nil,
        addedAt: Date,
        sortIndex: Int,
        watchedAt: Date? = nil
    ) {
        self.videoID = videoID
        self.title = title
        self.author = author
        self.duration = duration
        self.addedAt = addedAt
        self.sortIndex = sortIndex
        self.watchedAt = watchedAt
    }

    public init(
        videoID: VideoID,
        title: String,
        author: String? = nil,
        duration: Double? = nil,
        addedAt: Date,
        sortIndex: Int,
        watchedAt: Date? = nil
    ) {
        self.init(
            videoID: videoID.rawValue, title: title, author: author, duration: duration,
            addedAt: addedAt, sortIndex: sortIndex, watchedAt: watchedAt
        )
    }
}

/// A resume position. Kept in its own table so a video played without being queued (a paste, a `cue://` link that
/// went straight to the player) still remembers where it stopped.
public struct ResumePosition: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "resumePosition"

    public var videoID: String
    public var position: Double
    public var duration: Double?
    public var updatedAt: Date

    public init(videoID: String, position: Double, duration: Double?, updatedAt: Date) {
        self.videoID = videoID
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
    }
}

/// A queued video with its resume position: what the sidebar and the totals read. Decoded from a left join, so the
/// resume columns are nil for a video that was never played.
public struct QueuedVideo: Codable, Equatable, Sendable, FetchableRecord {
    public var videoID: String
    public var title: String
    public var author: String?
    public var duration: Double?
    public var addedAt: Date
    public var sortIndex: Int
    public var watchedAt: Date?
    public var resumePosition: Double?
    public var resumeDuration: Double?
    public var resumeUpdatedAt: Date?

    public init(
        videoID: String,
        title: String,
        author: String? = nil,
        duration: Double? = nil,
        addedAt: Date,
        sortIndex: Int,
        watchedAt: Date? = nil,
        resumePosition: Double? = nil,
        resumeDuration: Double? = nil,
        resumeUpdatedAt: Date? = nil
    ) {
        self.videoID = videoID
        self.title = title
        self.author = author
        self.duration = duration
        self.addedAt = addedAt
        self.sortIndex = sortIndex
        self.watchedAt = watchedAt
        self.resumePosition = resumePosition
        self.resumeDuration = resumeDuration
        self.resumeUpdatedAt = resumeUpdatedAt
    }

    public var isWatched: Bool { watchedAt != nil }

    /// Nil only for a row whose id this build cannot validate.
    public var video: VideoID? { VideoID(videoID) }

    /// Seconds left to watch: the duration minus a resume position inside it. A position at or past the duration is
    /// not a half-watched video but a bogus position, so the whole duration is still to watch. `QueueStore.summary()`
    /// applies the same rule, in SQL. Nil when the duration is unknown.
    public var remainingDuration: Double? {
        guard let duration, duration > 0 else { return nil }
        guard let resumePosition, resumePosition > 0, resumePosition < duration else { return duration }
        return duration - resumePosition
    }
}
