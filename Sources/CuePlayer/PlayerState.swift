import CueMPV
import Foundation

public enum EndReason: Equatable, Sendable {
    case finished
    case stopped
    case failed(String)
}

/// Player-level events, independent of libmpv.
public enum EngineEvent: Equatable, Sendable {
    case fileLoaded
    case playbackRestarted
    case position(Double)
    case duration(Double?)
    case paused(Bool)
    case buffering(Bool)
    /// The media time the stream has loaded up to, or nil when nothing is cached.
    case bufferedUntil(Double?)
    case volume(Double)
    case muted(Bool)
    case videoSize(VideoSize)
    case ended(EndReason)
}

/// What the UI shows. Updated only on the main actor, by `PlayerController`.
public struct PlayerState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case resolving
        case loading
        case ready
        case ended
        case failed(String)
    }

    public var phase: Phase = .idle
    public var stream: PlayableStream?
    public var position = 0.0
    public var duration: Double?
    public var isPaused = false
    public var isBuffering = false
    /// How far ahead the stream has loaded, in media time. A fresh `PlayerState` per video resets it.
    public var bufferedUntil: Double?
    public var volume = 100.0
    public var isMuted = false
    /// The source's announced size before playback, then mpv's reported display size.
    public var videoSize: VideoSize?

    public init() {}

    /// The window's title: the stream's title, or the app's name before anything is open.
    public var windowTitle: String {
        stream?.title ?? "Cue"
    }

    /// Shown under the title. Software decoding is worth surfacing: it costs far more CPU than the hardware path.
    public var windowSubtitle: String {
        stream?.decoding == .software ? "Software decoding" : ""
    }

    public mutating func apply(_ event: EngineEvent) {
        switch event {
        case .fileLoaded:
            if phase == .ready || phase == .ended { phase = .loading }
        case .playbackRestarted:
            if phase == .loading || phase == .ended { phase = .ready }
        case let .position(seconds):
            position = seconds
        case let .duration(seconds):
            duration = seconds
        case let .paused(paused):
            isPaused = paused
        case let .buffering(buffering):
            isBuffering = buffering
        case let .bufferedUntil(seconds):
            bufferedUntil = seconds
        case let .volume(level):
            volume = level
        case let .muted(muted):
            isMuted = muted
        case let .videoSize(size):
            videoSize = size
        case .ended(.finished):
            phase = .ended
        case let .ended(.failed(message)):
            phase = .failed(message)
        case .ended(.stopped):
            break
        }
    }
}

/// Turns batches of mpv events into `EngineEvent`s.
public struct EngineEventMapper: Sendable {
    private var displayWidth = 0
    private var displayHeight = 0
    private var rotation = 0
    private var reportedSize: VideoSize?

    public init() {}

    /// Maps one drained batch. A video size is emitted once per batch, after all its property changes, and only when
    /// it changed. mpv reports zero sizes while tearing a file down: those emit nothing, and clear the remembered
    /// size so the next file is reported even if it happens to have the same dimensions.
    public mutating func map(_ batch: [MPVEvent]) -> [EngineEvent] {
        var events: [EngineEvent] = []
        for event in batch {
            events += map(event)
        }
        guard let size = currentSize() else {
            reportedSize = nil
            return events
        }
        if size != reportedSize {
            reportedSize = size
            events.append(.videoSize(size))
        }
        return events
    }

    private mutating func map(_ event: MPVEvent) -> [EngineEvent] {
        switch event {
        case .fileLoaded:
            // A new file: forget the previous one's size, so the window refits even for identical dimensions.
            displayWidth = 0
            displayHeight = 0
            rotation = 0
            reportedSize = nil
            return [.fileLoaded]
        case .playbackRestart:
            return [.playbackRestarted]
        case .endFile(.endOfFile):
            return [.ended(.finished)]
        case let .endFile(.error(code)):
            return [.ended(.failed(MPVError.message(for: code)))]
        case .endFile:
            return [.ended(.stopped)]
        case let .propertyChange(_, name, value):
            return mapProperty(name, value)
        default:
            return []
        }
    }

    private mutating func mapProperty(_ name: String, _ value: MPVValue) -> [EngineEvent] {
        switch (name, value) {
        case let ("time-pos", .double(seconds)): return [.position(seconds)]
        case let ("duration", .double(seconds)): return [.duration(seconds)]
        case ("duration", .none): return [.duration(nil)]
        case let ("pause", .flag(paused)): return [.paused(paused)]
        case let ("paused-for-cache", .flag(buffering)): return [.buffering(buffering)]
        case let ("demuxer-cache-time", .double(seconds)): return [.bufferedUntil(seconds)]
        case ("demuxer-cache-time", .none): return [.bufferedUntil(nil)]
        case ("eof-reached", .flag(true)): return [.ended(.finished)]
        case let ("volume", .double(level)): return [.volume(level)]
        case let ("mute", .flag(muted)): return [.muted(muted)]
        case ("video-params/dw", _): displayWidth = Self.integer(value)
        case ("video-params/dh", _): displayHeight = Self.integer(value)
        case ("video-params/rotate", _): rotation = Self.integer(value)
        default: break
        }
        return []
    }

    private func currentSize() -> VideoSize? {
        guard displayWidth > 0, displayHeight > 0 else { return nil }
        let quarterTurn = rotation % 180 != 0
        return VideoSize(width: quarterTurn ? displayHeight : displayWidth, height: quarterTurn ? displayWidth : displayHeight)
    }

    private static func integer(_ value: MPVValue) -> Int {
        if case let .int64(number) = value { Int(number) } else { 0 }
    }
}
