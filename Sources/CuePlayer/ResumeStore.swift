import CueCore
import Foundation
import os

public struct ResumeEntry: Codable, Equatable, Sendable {
    public var position: Double
    public var duration: Double?
    public var updatedAt: Date

    public init(position: Double, duration: Double?, updatedAt: Date) {
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
    }
}

/// Where resume positions live. `JSONResumeStore` is a stopgap: the queue's database can implement this protocol
/// later without touching the player.
@MainActor
public protocol ResumeStore: AnyObject {
    func entry(for videoID: VideoID) -> ResumeEntry?
    func save(_ entry: ResumeEntry, for videoID: VideoID)
    func remove(_ videoID: VideoID)
}

public struct ResumePolicy: Equatable, Sendable {
    /// Positions before this are not worth resuming.
    public var minimumPosition: Double
    /// Positions this close to the end count as watched.
    public var endMargin: Double

    public init(minimumPosition: Double = 10, endMargin: Double = 20) {
        self.minimumPosition = minimumPosition
        self.endMargin = endMargin
    }

    public func isWorthKeeping(position: Double, duration: Double?) -> Bool {
        guard position >= minimumPosition else { return false }
        guard let duration else { return true }
        return position < duration - endMargin
    }

    /// Where to start a video: the saved position when worth resuming, otherwise nil (from the beginning).
    public func startPosition(for entry: ResumeEntry?) -> Double? {
        guard let entry, isWorthKeeping(position: entry.position, duration: entry.duration) else { return nil }
        return entry.position
    }
}

/// Resume positions in one small JSON file, rewritten atomically on every change.
@MainActor
public final class JSONResumeStore: ResumeStore {
    private struct Contents: Codable {
        var version: Int
        var entries: [String: ResumeEntry]
    }

    public static let formatVersion = 1

    public let fileURL: URL
    private let limit: Int
    private var entries: [String: ResumeEntry]
    private let logger = Logger(subsystem: "com.neverbot.cue", category: "resume")

    /// `~/Library/Application Support/Cue/resume-positions.json`.
    public static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Cue", directoryHint: .isDirectory)
            .appending(path: "resume-positions.json", directoryHint: .notDirectory)
    }

    /// Only the app target should point this at the real profile; use `JSONResumeStore.default()` for that, so a
    /// future zero-argument call from a test cannot silently write into the user's real Application Support.
    public init(fileURL: URL, limit: Int = 1000) {
        self.fileURL = fileURL
        self.limit = limit
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL),
           let contents = try? decoder.decode(Contents.self, from: data),
           contents.version == Self.formatVersion {
            entries = contents.entries
        } else {
            entries = [:]
        }
    }

    public func entry(for videoID: VideoID) -> ResumeEntry? {
        entries[videoID.rawValue]
    }

    public func save(_ entry: ResumeEntry, for videoID: VideoID) {
        entries[videoID.rawValue] = entry
        if entries.count > limit {
            let newest = entries.sorted { $0.value.updatedAt > $1.value.updatedAt }.prefix(limit)
            entries = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
        write()
    }

    public func remove(_ videoID: VideoID) {
        guard entries.removeValue(forKey: videoID.rawValue) != nil else { return }
        write()
    }

    /// The store backed by the real `~/Library/Application Support/Cue/resume-positions.json`. Only the app target
    /// should call this; tests must pass an explicit `fileURL` instead.
    public static func `default`() -> JSONResumeStore {
        JSONResumeStore(fileURL: defaultFileURL)
    }

    private func write() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(Contents(version: Self.formatVersion, entries: entries)).write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Could not save resume positions: \(String(describing: error), privacy: .public)")
        }
    }
}
