import CueCore
import Foundation

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

/// Where resume positions live. The player knows this protocol and nothing else: the queue's database implements it
/// (`DatabaseResumeStore`), so how a position is stored is not the player's business.
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
