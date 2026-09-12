import CueCore
import Foundation

/// Opens videos, forwards commands to the engine, keeps `PlayerState` and resume positions current, and re-resolves
/// streams whose URLs have expired.
@MainActor
public final class PlayerController {
    public private(set) var state = PlayerState() {
        didSet {
            if state != oldValue { onStateChange?(state) }
        }
    }

    public var onStateChange: ((PlayerState) -> Void)?

    private let engine: PlaybackEngine
    private let resolver: StreamResolving
    private let resumeStore: ResumeStore
    private let policy: ResumePolicy
    private let now: () -> Date
    private let saveInterval: TimeInterval
    /// Increments on every open, refresh and close, so a slow resolution cannot start a video the user moved past.
    private var generation = 0
    private var lastSavedAt: Date?
    /// One automatic refresh per playback attempt, so a video that keeps failing does not resolve in a loop.
    private var refreshedAfterFailure = false

    public init(
        engine: PlaybackEngine,
        resolver: StreamResolving,
        resumeStore: ResumeStore,
        policy: ResumePolicy = ResumePolicy(),
        saveInterval: TimeInterval = 5,
        now: @escaping () -> Date = { Date() }
    ) {
        self.engine = engine
        self.resolver = resolver
        self.resumeStore = resumeStore
        self.policy = policy
        self.saveInterval = saveInterval
        self.now = now
        engine.onEvent = { [weak self] event in self?.handle(event) }
    }

    public func open(_ input: LaunchInput) async {
        saveResumePosition()
        generation += 1
        let current = generation
        refreshedAfterFailure = false

        var next = PlayerState()
        next.volume = state.volume
        next.isMuted = state.isMuted
        switch input {
        case let .file(url):
            state = next
            start(PlayableStream(fileURL: url), at: nil)
        case let .video(videoID):
            next.phase = .resolving
            state = next
            do {
                let stream = try await resolver.stream(for: videoID)
                guard current == generation else { return }
                start(stream, at: policy.startPosition(for: resumeStore.entry(for: videoID)))
            } catch {
                guard current == generation else { return }
                state.phase = .failed(Self.message(for: error))
            }
        }
    }

    /// Commands are ignored while a resolution is in flight, so repeated key presses cannot start several of them.
    public func perform(_ command: PlayerCommand) {
        guard state.stream != nil, command.mpvArguments != nil, state.phase != .resolving else { return }
        if let position = refreshTarget(for: command) {
            Task { await refreshStream(resumeAt: position) }
            return
        }
        if command == .togglePause, !state.isPaused {
            saveResumePosition()
        }
        engine.perform(command)
    }

    /// Saves the current position, or forgets it when it is not worth resuming. Only while a video is playing:
    /// before playback starts the position is not meaningful yet.
    public func saveResumePosition() {
        guard state.phase == .ready, let videoID = state.stream?.videoID else { return }
        lastSavedAt = now()
        persist(position: state.position, duration: state.duration, for: videoID)
    }

    public func close() {
        saveResumePosition()
        generation += 1
        engine.stop()
        state.phase = .idle
    }

    private var streamNeedsRefresh: Bool {
        StreamFreshness.needsRefresh(expiresAt: state.stream?.expiresAt, now: now())
    }

    /// The position a command would need fresh URLs for, or nil when the current ones still work.
    private func refreshTarget(for command: PlayerCommand) -> Double? {
        guard streamNeedsRefresh, state.stream?.videoID != nil else { return nil }
        switch command {
        case .togglePause where state.isPaused: return state.position
        case let .seekRelative(seconds): return max(0, state.position + seconds)
        case let .seekAbsolute(seconds): return max(0, seconds)
        default: return nil
        }
    }

    private func persist(position: Double, duration: Double?, for videoID: VideoID) {
        if policy.isWorthKeeping(position: position, duration: duration) {
            resumeStore.save(ResumeEntry(position: position, duration: duration, updatedAt: now()), for: videoID)
        } else {
            resumeStore.remove(videoID)
        }
    }

    private func start(_ stream: PlayableStream, at position: Double?) {
        state.stream = stream
        state.phase = .loading
        state.position = position ?? 0
        state.duration = stream.duration
        state.videoSize = stream.videoSize
        lastSavedAt = now()
        engine.setPaused(false)
        engine.load(LoadRequest(stream: stream, start: position))
    }

    private func refreshStream(resumeAt position: Double) async {
        guard let videoID = state.stream?.videoID, state.phase != .resolving else { return }
        generation += 1
        let current = generation
        state.phase = .resolving
        do {
            let stream = try await resolver.stream(for: videoID)
            guard current == generation else { return }
            start(stream, at: position)
        } catch {
            guard current == generation else { return }
            state.phase = .failed(Self.message(for: error))
        }
    }

    private func handle(_ event: EngineEvent) {
        state.apply(event)
        switch event {
        case .playbackRestarted:
            refreshedAfterFailure = false
        case .position:
            if !state.isPaused, let lastSavedAt, now().timeIntervalSince(lastSavedAt) >= saveInterval {
                saveResumePosition()
            }
        case .paused(true):
            saveResumePosition()
        case .ended(.finished):
            handlePlaybackEnd()
        case .ended(.failed):
            refreshAfterFailure(resumeAt: state.position)
        default:
            break
        }
    }

    /// With `keep-open=yes` mpv reports the end of the file whenever playback stops, including when a stream dies
    /// early (an expired URL, a dropped connection). Only an end close to the duration means the video was watched.
    private func handlePlaybackEnd() {
        guard let videoID = state.stream?.videoID else { return }
        let position = state.position
        guard let duration = state.duration, position < duration - policy.endMargin else {
            resumeStore.remove(videoID)
            return
        }
        // `saveResumePosition()` does nothing now that the phase is `.ended`, so write the entry directly.
        persist(position: position, duration: duration, for: videoID)
        refreshAfterFailure(resumeAt: position)
    }

    private func refreshAfterFailure(resumeAt position: Double) {
        guard !refreshedAfterFailure, streamNeedsRefresh else { return }
        refreshedAfterFailure = true
        Task { await refreshStream(resumeAt: position) }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
