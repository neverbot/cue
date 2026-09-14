import Foundation
import GRDB

/// The SQLite database behind the queue: one file, opened through a serialized `DatabaseQueue` (a desktop app has one
/// writer and no concurrent readers worth a pool), with every schema change registered as a migration.
public struct QueueDatabase: Sendable {
    public let writer: DatabaseQueue

    private init(writer: DatabaseQueue) {
        self.writer = writer
    }

    /// `~/Library/Application Support/Cue/queue.sqlite`, beside the player's own data.
    public static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Cue", directoryHint: .isDirectory)
            .appending(path: "queue.sqlite", directoryHint: .notDirectory)
    }

    /// Opens (creating the directory and the file if needed) and migrates the database at `fileURL`.
    /// Only the app target should pass `defaultFileURL`; tests pass a file in a temporary directory.
    ///
    /// The queue is a record of what the user watches, so the directory is created `rwx------` and the file is set to
    /// `rw-------`: on a shared Mac another account has no business reading it.
    public static func open(at fileURL: URL) throws -> QueueDatabase {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let writer = try DatabaseQueue(path: fileURL.path, configuration: configuration)
        try migrator.migrate(writer)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        return QueueDatabase(writer: writer)
    }

    /// A migrated database that exists only for the lifetime of the process. Tests use it; nothing else should.
    public static func inMemory() throws -> QueueDatabase {
        let writer = try DatabaseQueue()
        try migrator.migrate(writer)
        return QueueDatabase(writer: writer)
    }

    /// Applied in order, every release. Never edit a registered migration: add another one.
    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-queue") { db in
            try db.create(table: "queueItem") { table in
                table.primaryKey("videoID", .text).notNull()
                table.column("title", .text).notNull()
                table.column("author", .text)
                table.column("duration", .double)
                table.column("addedAt", .datetime).notNull()
                table.column("sortIndex", .integer).notNull()
                table.column("watchedAt", .datetime)
            }
            try db.create(indexOn: "queueItem", columns: ["sortIndex"])
            try db.create(table: "resumePosition") { table in
                table.primaryKey("videoID", .text).notNull()
                table.column("position", .double).notNull()
                table.column("duration", .double)
                table.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "metadata") { table in
                table.primaryKey("key", .text).notNull()
                table.column("value", .text).notNull()
            }
        }
        // A title that is not known yet is now null, rather than the video id standing in for one. The old
        // placeholder and a genuine title were indistinguishable, so nothing could tell what was known from what was
        // merely filled in. SQLite cannot drop a NOT NULL constraint, so the table is rebuilt: every row is carried
        // over, and only the rows whose title was exactly their own id - the placeholder `add` used to write - become
        // null. A real title survives untouched, including the perverse one that happens to read like an id, which is
        // now simply a title like any other.
        migrator.registerMigration("v2-unknown-title") { db in
            try db.create(table: "newQueueItem") { table in
                table.primaryKey("videoID", .text).notNull()
                table.column("title", .text)
                table.column("author", .text)
                table.column("duration", .double)
                table.column("addedAt", .datetime).notNull()
                table.column("sortIndex", .integer).notNull()
                table.column("watchedAt", .datetime)
            }
            try db.execute(sql: """
            INSERT INTO newQueueItem (videoID, title, author, duration, addedAt, sortIndex, watchedAt)
            SELECT videoID, CASE WHEN title = videoID THEN NULL ELSE title END,
                   author, duration, addedAt, sortIndex, watchedAt
            FROM queueItem
            """)
            try db.drop(table: "queueItem")
            try db.rename(table: "newQueueItem", to: "queueItem")
            // The index went with the old table.
            try db.create(indexOn: "queueItem", columns: ["sortIndex"])
        }
        return migrator
    }

    /// The migration names this build knows, newest last. Used by the tests that pin the schema.
    public static var migrationNames: [String] {
        migrator.migrations
    }
}
