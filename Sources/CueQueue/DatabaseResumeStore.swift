import CueCore
import CuePlayer
import Foundation
import os

/// The database implementation of the player's `ResumeStore`. Positions live in the `resumePosition` table, for
/// queued and unqueued videos alike.
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
