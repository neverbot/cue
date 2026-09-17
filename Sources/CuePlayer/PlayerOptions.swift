import CueMPV
import Foundation

public struct MPVOption: Equatable, Sendable {
    public let name: String
    public let value: String

    public init(_ name: String, _ value: String) {
        self.name = name
        self.value = value
    }
}

public enum PlayerOptions {
    /// Options applied before `mpv_initialize`.
    ///
    /// Scripts stay off: under the hardened runtime, mpv's built-in Lua scripts get the process killed by code-signing
    /// enforcement, and Cue draws its own controls. Never add an option that loads a script.
    /// Where streams are cached while they play: `~/Library/Caches/Cue/stream-cache`. mpv unlinks each file as soon
    /// as it creates it, so nothing is left here once playback stops, even after a crash.
    public static var defaultStreamCacheDirectory: URL {
        URL.cachesDirectory
            .appending(path: "Cue", directoryHint: .isDirectory)
            .appending(path: "stream-cache", directoryHint: .isDirectory)
    }

    /// The stream cache, for when a connection cannot keep up.
    ///
    /// Measured against Cue's own libmpv on a real stream: mpv keeps filling its cache while paused, and its default
    /// cap (150 MiB) stops it at roughly six minutes of 1080p. Pausing to let a slow connection catch up therefore
    /// only ever banked a few minutes. These raise the cap to 512 MiB — about twenty minutes — and put it **on disk**
    /// rather than in memory, because two demuxers (video and the separate audio stream) each hold their own cache and
    /// the app is meant to stay light. That the disk cache spares memory is mpv's documented behaviour; the probe that
    /// tried to measure it drowned in the test process's own allocation noise.
    ///
    /// `cache-pause-wait` goes from 1 s to 3 s: when the cache runs dry mpv pauses, and resuming after only one second
    /// of data on a poor connection is what made playback stutter in short, repeated stops.
    public static func streamCache(directory: String) -> [MPVOption] {
        [
            MPVOption("cache-on-disk", "yes"),
            MPVOption("demuxer-cache-dir", directory),
            MPVOption("demuxer-max-bytes", "512MiB"),
            MPVOption("cache-pause-wait", "3"),
        ]
    }

    public static func baseline(videoOutput: String = "libmpv", audioOutput: String? = nil) -> [MPVOption] {
        var options = [
            MPVOption("vo", videoOutput),
            MPVOption("hwdec", "videotoolbox"),
            MPVOption("config", "no"),
            MPVOption("load-scripts", "no"),
            MPVOption("osc", "no"),
            MPVOption("load-stats-overlay", "no"),
            MPVOption("load-console", "no"),
            MPVOption("load-auto-profiles", "no"),
            MPVOption("load-select", "no"),
            MPVOption("load-positioning", "no"),
            MPVOption("load-commands", "no"),
            MPVOption("load-context-menu", "no"),
            MPVOption("ytdl", "no"),
            MPVOption("input-default-bindings", "no"),
            MPVOption("input-vo-keyboard", "no"),
            MPVOption("terminal", "no"),
            MPVOption("osd-level", "0"),
            MPVOption("idle", "yes"),
            MPVOption("keep-open", "yes"),
            MPVOption("volume-max", "100"),
        ]
        if let audioOutput { options.append(MPVOption("ao", audioOutput)) }
        return options
    }

    /// Properties the engine observes; `EngineEventMapper` turns their changes into `EngineEvent`s.
    public static let observedProperties: [(name: String, format: MPVFormat)] = [
        ("time-pos", .double),
        ("duration", .double),
        ("pause", .flag),
        ("paused-for-cache", .flag),
        // How far ahead the stream has loaded, in media time — drawn on the seek bar.
        ("demuxer-cache-time", .double),
        ("eof-reached", .flag),
        ("volume", .double),
        ("mute", .flag),
        ("video-params/dw", .int64),
        ("video-params/dh", .int64),
        ("video-params/rotate", .int64),
    ]
}

/// One `loadfile` invocation.
public struct LoadRequest: Equatable, Sendable {
    public var stream: PlayableStream
    public var start: Double?

    public init(stream: PlayableStream, start: Double?) {
        self.stream = stream
        self.start = start
    }

    /// `loadfile <url> replace -1 <per-file options>`. Per-file option values use mpv's `%<bytes>%<value>` quoting:
    /// URLs and user agents contain `,` and `:`, and `audio-files` (without `-append`) would split URLs on `:`.
    public var arguments: [String] {
        var options: [String] = []
        if let audioURL = stream.audioURL {
            options.append("audio-files-append=" + Self.quoted(Self.mpvPath(audioURL)))
        }
        if let userAgent = stream.userAgent {
            options.append("user-agent=" + Self.quoted(userAgent))
        }
        if let start, start > 0 {
            options.append("start=\(start)")
        }
        var arguments = ["loadfile", Self.mpvPath(stream.videoURL), "replace"]
        if !options.isEmpty {
            arguments += ["-1", options.joined(separator: ",")]
        }
        return arguments
    }

    static func quoted(_ value: String) -> String {
        "%\(value.utf8.count)%\(value)"
    }

    static func mpvPath(_ url: URL) -> String {
        url.isFileURL ? url.path : url.absoluteString
    }
}
