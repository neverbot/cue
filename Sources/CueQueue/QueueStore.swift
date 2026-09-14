import CueCore
import CuePlayer
import Foundation
import GRDB

/// Where a newly added video goes.
public enum QueuePosition: Sendable, Equatable {
    /// After everything already queued.
    case end
    /// Before everything already queued: the next video to play.
    case front
}

/// Counts for the sidebar's header.
public struct QueueSummary: Equatable, Sendable {
    public var pendingCount: Int
    public var watchedCount: Int

    public init(pendingCount: Int = 0, watchedCount: Int = 0) {
        self.pendingCount = pendingCount
        self.watchedCount = watchedCount
    }
}

/// Every read and write the queue needs. Synchronous: SQLite on a local file is fast enough that the UI can call it
/// directly, and a synchronous store keeps the callers (and their tests) free of actor hops.
public struct QueueStore: Sendable {
    public let database: QueueDatabase

    public init(database: QueueDatabase) {
        self.database = database
    }

    /// Left join of `queueItem` and `resumePosition`, in queue order.
    private static let queuedVideoSQL = """
    SELECT q.videoID, q.title, q.author, q.duration, q.addedAt, q.sortIndex, q.watchedAt,
           r.position AS resumePosition, r.duration AS resumeDuration, r.updatedAt AS resumeUpdatedAt
    FROM queueItem q LEFT JOIN resumePosition r ON r.videoID = q.videoID
    """

    // MARK: - Reading

    public func videos(includingWatched: Bool = true) throws -> [QueuedVideo] {
        let filter = includingWatched ? "" : "WHERE q.watchedAt IS NULL "
        return try database.writer.read { db in
            try QueuedVideo.fetchAll(db, sql: Self.queuedVideoSQL + " " + filter + "ORDER BY q.sortIndex, q.addedAt")
        }
    }

    public func video(for videoID: VideoID) throws -> QueuedVideo? {
        try database.writer.read { db in
            try QueuedVideo.fetchOne(db, sql: Self.queuedVideoSQL + " WHERE q.videoID = ?", arguments: [videoID.rawValue])
        }
    }

    public func contains(_ videoID: VideoID) throws -> Bool {
        try database.writer.read { db in
            try QueueItem.filter(key: videoID.rawValue).fetchCount(db) > 0
        }
    }

    /// The first pending video in queue order, skipping `excluding` (the one already playing).
    public func nextPending(excluding: VideoID? = nil) throws -> QueuedVideo? {
        try database.writer.read { db in
            try QueuedVideo.fetchOne(
                db,
                sql: Self.queuedVideoSQL + " WHERE q.watchedAt IS NULL AND q.videoID IS NOT ? ORDER BY q.sortIndex, q.addedAt LIMIT 1",
                arguments: [excluding?.rawValue]
            )
        }
    }

    /// How many videos are still pending and how many are already watched.
    public func summary() throws -> QueueSummary {
        try database.writer.read { db in
            let row = try Row.fetchOne(db, sql: """
            SELECT
              SUM(watchedAt IS NULL) AS pending,
              SUM(watchedAt IS NOT NULL) AS watched
            FROM queueItem
            """)
            guard let row else { return QueueSummary() }
            return QueueSummary(pendingCount: row["pending"] ?? 0, watchedCount: row["watched"] ?? 0)
        }
    }

    // MARK: - Writing

    /// Adds a video. Returns false and changes nothing when it is already queued, which is what makes importing and
    /// repeated `cue://add` links idempotent.
    @discardableResult
    public func add(
        _ videoID: VideoID,
        title: String? = nil,
        author: String? = nil,
        duration: Double? = nil,
        at position: QueuePosition = .end,
        addedAt: Date = Date()
    ) throws -> Bool {
        try database.writer.write { db in
            guard try QueueItem.filter(key: videoID.rawValue).fetchCount(db) == 0 else { return false }
            let item = QueueItem(
                videoID: videoID,
                title: title,
                author: author,
                duration: duration,
                addedAt: addedAt,
                sortIndex: try Self.sortIndex(for: position, in: db)
            )
            try item.insert(db)
            return true
        }
    }

    /// Fills in what the extractor learned about a video the first time it played, without disturbing its place in
    /// the queue. Does nothing for a video that is not queued.
    ///
    /// The title is only written while none is known, so a title that came from an imported file is never
    /// overwritten by whatever YouTube reports today - including the one that happens to read like a video id, which
    /// is a title like any other now that an unknown one is null. Author and duration fill in whenever they are
    /// still missing.
    public func updateMetadata(for videoID: VideoID, title: String, author: String?, duration: Double?) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                UPDATE queueItem
                SET title = COALESCE(title, ?),
                    author = COALESCE(author, ?),
                    duration = COALESCE(duration, ?)
                WHERE videoID = ?
                """,
                arguments: [title, author, duration, videoID.rawValue]
            )
        }
    }

    /// Removing a video from the queue also forgets where it was watched to: a resume position is a record of what
    /// was played, and leaving it behind would keep it as a permanent trace of a video the owner deliberately
    /// removed. (Resume positions for a video that was never queued at all are unaffected: that independence, for a
    /// paste or a `cue://` link that went straight to the player, is deliberate — see `ResumePosition`.)
    public func remove(_ videoID: VideoID) throws {
        _ = try database.writer.write { db in
            try QueueItem.deleteOne(db, key: videoID.rawValue)
            try ResumePosition.deleteOne(db, key: videoID.rawValue)
        }
    }

    /// Clears the queue and, for exactly the videos that were in it, their resume positions too — see `remove(_:)`.
    public func removeAll() throws {
        _ = try database.writer.write { db in
            let ids = try String.fetchAll(db, sql: "SELECT videoID FROM queueItem")
            try QueueItem.deleteAll(db)
            try ResumePosition.deleteAll(db, keys: ids)
        }
    }

    /// Moves a video so that it sits at `index` in queue order (0 is the front). Rewrites the whole order, which is
    /// cheap for a personal queue and keeps the indices dense and predictable.
    public func move(_ videoID: VideoID, to index: Int) throws {
        try database.writer.write { db in
            var ids = try String.fetchAll(db, sql: "SELECT videoID FROM queueItem ORDER BY sortIndex, addedAt")
            guard let current = ids.firstIndex(of: videoID.rawValue) else { return }
            ids.remove(at: current)
            ids.insert(videoID.rawValue, at: min(max(index, 0), ids.count))
            for (offset, id) in ids.enumerated() {
                try db.execute(sql: "UPDATE queueItem SET sortIndex = ? WHERE videoID = ?", arguments: [offset, id])
            }
        }
    }

    public func markWatched(_ videoID: VideoID, at date: Date = Date()) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE queueItem SET watchedAt = ? WHERE videoID = ?", arguments: [date, videoID.rawValue])
            try ResumePosition.deleteOne(db, key: videoID.rawValue)
        }
    }

    public func markUnwatched(_ videoID: VideoID) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE queueItem SET watchedAt = NULL WHERE videoID = ?", arguments: [videoID.rawValue])
        }
    }

    // MARK: - Resume positions

    public func resumeEntry(for videoID: VideoID) throws -> ResumeEntry? {
        try database.writer.read { db in
            try ResumePosition.fetchOne(db, key: videoID.rawValue)
        }.map { ResumeEntry(position: $0.position, duration: $0.duration, updatedAt: $0.updatedAt) }
    }

    public func saveResumeEntry(_ entry: ResumeEntry, for videoID: VideoID) throws {
        let row = ResumePosition(
            videoID: videoID.rawValue, position: entry.position, duration: entry.duration, updatedAt: entry.updatedAt
        )
        try database.writer.write { db in
            try row.save(db)
        }
    }

    public func removeResumeEntry(for videoID: VideoID) throws {
        _ = try database.writer.write { db in
            try ResumePosition.deleteOne(db, key: videoID.rawValue)
        }
    }

    /// Inserts a resume position only when the video has none, for importing the player's old JSON file.
    /// Returns whether it was inserted.
    @discardableResult
    public func addResumeEntryIfMissing(_ entry: ResumeEntry, for videoID: VideoID) throws -> Bool {
        try database.writer.write { db in
            guard try ResumePosition.filter(key: videoID.rawValue).fetchCount(db) == 0 else { return false }
            try ResumePosition(
                videoID: videoID.rawValue, position: entry.position, duration: entry.duration, updatedAt: entry.updatedAt
            ).insert(db)
            return true
        }
    }

    // MARK: - Metadata

    public func metadata(_ key: String) throws -> String? {
        try database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM metadata WHERE key = ?", arguments: [key])
        }
    }

    public func setMetadata(_ key: String, to value: String) throws {
        try database.writer.write { db in
            try db.execute(sql: "INSERT INTO metadata (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = ?",
                           arguments: [key, value, value])
        }
    }

    private static func sortIndex(for position: QueuePosition, in db: Database) throws -> Int {
        switch position {
        case .end:
            return (try Int.fetchOne(db, sql: "SELECT MAX(sortIndex) FROM queueItem") ?? -1) + 1
        case .front:
            return (try Int.fetchOne(db, sql: "SELECT MIN(sortIndex) FROM queueItem") ?? 1) - 1
        }
    }
}
