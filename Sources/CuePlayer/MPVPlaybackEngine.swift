import CueMPV
import Foundation
import os

/// `PlaybackEngine` on libmpv. The video layer creates its render context from `handle`.
@MainActor
public final class MPVPlaybackEngine: PlaybackEngine {
    public let handle: MPVHandle
    public var onEvent: ((EngineEvent) -> Void)?
    private var mapper = EngineEventMapper()
    private let logger = Logger(subsystem: "com.neverbot.cue", category: "mpv")

    /// `videoOutput` stays `libmpv` in the app (render API); tests pass `null`.
    /// `streamCacheDirectory` puts the stream cache on disk there with a larger cap; the app passes
    /// `PlayerOptions.defaultStreamCacheDirectory`, tests leave it nil and get mpv's in-memory default.
    public init(videoOutput: String = "libmpv", audioOutput: String? = nil, streamCacheDirectory: URL? = nil) throws {
        handle = try MPVHandle()
        var options = PlayerOptions.baseline(videoOutput: videoOutput, audioOutput: audioOutput)
        if let streamCacheDirectory,
           (try? FileManager.default.createDirectory(at: streamCacheDirectory, withIntermediateDirectories: true)) != nil {
            // Only when the directory exists: an unwritable cache dir would fail every stream, while mpv's in-memory
            // default at least plays.
            options += PlayerOptions.streamCache(directory: streamCacheDirectory.path)
        }
        for option in options {
            try handle.setOption(option.name, option.value)
        }
        // The handler holds the engine until `shutdown()` clears it; events hop to the main queue in order.
        try handle.initialize { events in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.receive(events) }
            }
        }
        do {
            try handle.requestLogMessages(minimumLevel: "warn")
            for property in PlayerOptions.observedProperties {
                try handle.observe(property.name, format: property.format)
            }
        } catch {
            // The core is running and holds a reference to this engine: tear it down instead of leaking it.
            try? handle.destroy()
            throw error
        }
    }

    public func load(_ request: LoadRequest) {
        send(request.arguments)
    }

    public func setPaused(_ paused: Bool) {
        do {
            try handle.setProperty("pause", paused ? "yes" : "no")
        } catch {
            logger.error("\(LogRedactor.redact(String(describing: error)), privacy: .public)")
        }
    }

    public func perform(_ command: PlayerCommand) {
        guard let arguments = command.mpvArguments else { return }
        send(arguments)
    }

    public func stop() {
        send(["stop"])
    }

    /// Destroys the core. The video layer must have freed its render context first.
    public func shutdown() throws {
        onEvent = nil
        try handle.destroy()
    }

    private func send(_ arguments: [String]) {
        do {
            try handle.command(arguments)
        } catch {
            logger.error("\(LogRedactor.redact(String(describing: error)), privacy: .public)")
            onEvent?(.ended(.failed(String(describing: error))))
        }
    }

    private func receive(_ batch: [MPVEvent]) {
        for case let .logMessage(prefix, level, text) in batch {
            let line = "[\(prefix)] \(LogRedactor.redact(text))"
            if level == "fatal" || level == "error" {
                logger.error("\(line, privacy: .public)")
            } else {
                logger.notice("\(line, privacy: .public)")
            }
        }
        for event in mapper.map(batch) {
            onEvent?(event)
        }
    }
}
