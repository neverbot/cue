import CueCore
import CuePlayer
import Foundation
import os

extension PlayerController: QueuePlaying {
    public var playerState: PlayerState { state }
}

/// Drives playback from the queue: plays a video, fills in what the extractor learned, marks a video watched when it
/// reaches the end, and moves on to the next one.
@MainActor
public final class QueueCoordinator {
    /// Whether finishing a video starts the next one.
    public var playsNextAutomatically = true
    /// Called after any change the sidebar should redraw for.
    public var onQueueChange: (() -> Void)?

    public private(set) var currentVideoID: VideoID?

    private let store: QueueStore
    private let player: any QueuePlaying
    private let policy: ResumePolicy
    private let now: () -> Date
    /// The video whose confirmed end was already acted on, so one `.ended` phase cannot mark it watched twice.
    private var handledEndFor: VideoID?
    /// Videos whose stored metadata was already filled in this session.
    private var describedVideos: Set<VideoID> = []
    private let logger = Logger(subsystem: "com.neverbot.cue", category: "queue")

    public init(
        store: QueueStore,
        player: any QueuePlaying,
        policy: ResumePolicy = ResumePolicy(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.player = player
        self.now = now
        self.policy = policy
    }

    /// Plays a specific video.
    public func play(_ videoID: VideoID) {
        currentVideoID = videoID
        handledEndFor = nil
        Task { await player.open(.video(videoID)) }
        onQueueChange?()
    }

    /// Plays the first pending video after the current one. Returns false when there is nothing left to play.
    @discardableResult
    public func playNext() -> Bool {
        guard let next = attempt({ try store.nextPending(excluding: currentVideoID) }) ?? nil,
              let videoID = next.video
        else { return false }
        play(videoID)
        return true
    }

    /// Adds a video and plays it straight away, for a paste or a `cue://add` link while nothing is playing.
    public func addAndPlay(_ videoID: VideoID, at position: QueuePosition = .front) {
        attempt { try store.add(videoID, at: position, addedAt: now()) }
        play(videoID)
    }

    public func markCurrentWatched() {
        guard let videoID = currentVideoID else { return }
        attempt { try store.markWatched(videoID, at: now()) }
        onQueueChange?()
    }

    /// Forwarded by the window controller on every player state change. The coordinator never subscribes to
    /// `PlayerController.onStateChange` itself: the window owns that callback.
    public func playerStateChanged(_ state: PlayerState) {
        guard let videoID = currentVideoID else { return }
        describe(state, for: videoID)
        guard state.phase == .ended else {
            // Playback moved on (a refresh, a re-resolve, a new load): a later genuine end must be acted on.
            handledEndFor = nil
            return
        }
        // Only a confirmed end counts as handled. A stream that dies early also reports `.ended`, and marking that
        // as handled would make the real finish, after the player re-resolves and plays on, do nothing.
        guard reachedTheEnd(state), handledEndFor != videoID else { return }
        handledEndFor = videoID
        attempt { try store.markWatched(videoID, at: now()) }
        onQueueChange?()
        if playsNextAutomatically, playNext() { return }
        currentVideoID = nil
    }

    /// Writes the title, author and duration the extractor reported into the queue, once per video per session.
    private func describe(_ state: PlayerState, for videoID: VideoID) {
        guard let stream = state.stream, stream.videoID == videoID,
              !stream.title.isEmpty, stream.title != videoID.rawValue,
              !describedVideos.contains(videoID)
        else { return }
        describedVideos.insert(videoID)
        attempt { try store.updateMetadata(for: videoID, title: stream.title, author: stream.author, duration: stream.duration) }
        onQueueChange?()
    }

    /// The player reports the end of the file whenever playback stops, so only an end near the duration counts as
    /// watched. An unknown duration never does: the stream may simply have died.
    private func reachedTheEnd(_ state: PlayerState) -> Bool {
        guard let duration = state.duration, duration > 0 else { return false }
        return state.position >= duration - policy.endMargin
    }

    @discardableResult
    private func attempt<Value>(_ work: () throws -> Value) -> Value? {
        do {
            return try work()
        } catch {
            logger.error("Queue database error: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
