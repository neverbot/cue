import CueCore
import CuePlayer
import Foundation
import os

/// The database implementation of the player's `ResumeStore`, replacing `JSONResumeStore`. Positions live in the
/// `resumePosition` table, for queued and unqueued videos alike.
@MainActor
public final class DatabaseResumeStore: ResumeStore {
    private let store: QueueStore
    private let logger = Logger(subsystem: "com.neverbot.cue", category: "queue")

    public init(store: QueueStore) {
        self.store = store
    }

    public func entry(for videoID: VideoID) -> ResumeEntry? {
        do {
            return try store.resumeEntry(for: videoID)
        } catch {
            logger.error("Could not read a resume position: \(String(describing: error), privacy: .private)")
            return nil
        }
    }

    public func save(_ entry: ResumeEntry, for videoID: VideoID) {
        do {
            try store.saveResumeEntry(entry, for: videoID)
        } catch {
            logger.error("Could not save a resume position: \(String(describing: error), privacy: .private)")
        }
    }

    public func remove(_ videoID: VideoID) {
        do {
            try store.removeResumeEntry(for: videoID)
        } catch {
            logger.error("Could not remove a resume position: \(String(describing: error), privacy: .private)")
        }
    }
}

/// Reads the player's `resume-positions.json` once, so upgrading keeps the positions the JSON store collected. The
/// file is never written, renamed or deleted: it stays where it is as a fallback, and a flag in `metadata` stops the
/// import from running again.
///
/// Main-actor isolated because `JSONResumeStore` is: this runs once at launch, from the app's own startup path.
@MainActor
public struct JSONResumeImport {
    /// Marks the one-time import as done for this database.
    public static let metadataKey = "resumeImport.json.v1"

    private struct Contents: Decodable {
        var version: Int
        var entries: [String: Entry]
    }

    private struct Entry: Decodable {
        var position: Double
        var duration: Double?
        var updatedAt: Date
    }

    public struct Report: Equatable, Sendable {
        /// Positions written into the database.
        public var imported: Int
        /// Videos that already had a position in the database.
        public var skipped: Int
        /// Keys that are not usable video ids.
        public var invalid: Int

        public init(imported: Int = 0, skipped: Int = 0, invalid: Int = 0) {
            self.imported = imported
            self.skipped = skipped
            self.invalid = invalid
        }
    }

    public let store: QueueStore

    public init(store: QueueStore) {
        self.store = store
    }

    /// Imports `fileURL` unless this database was imported before. A missing or unreadable file still marks the
    /// import done: there is nothing to retry.
    @discardableResult
    public func runIfNeeded(from fileURL: URL) throws -> Report {
        guard try store.metadata(Self.metadataKey) == nil else { return Report() }
        let report = try importEntries(from: fileURL)
        try store.setMetadata(Self.metadataKey, to: "done")
        return report
    }

    private func importEntries(from fileURL: URL) throws -> Report {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let contents = try? decoder.decode(Contents.self, from: data),
              contents.version == JSONResumeStore.formatVersion
        else { return Report() }

        var report = Report()
        for (key, entry) in contents.entries.sorted(by: { $0.key < $1.key }) {
            guard let videoID = VideoID(key) else {
                report.invalid += 1
                continue
            }
            let resume = ResumeEntry(position: entry.position, duration: entry.duration, updatedAt: entry.updatedAt)
            if try store.addResumeEntryIfMissing(resume, for: videoID) {
                report.imported += 1
            } else {
                report.skipped += 1
            }
        }
        return report
    }
}
