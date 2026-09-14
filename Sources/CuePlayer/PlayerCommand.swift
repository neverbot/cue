import Foundation

/// User intents, from the keyboard, the menu or the on-screen controls.
public enum PlayerCommand: Equatable, Sendable {
    case togglePause
    case seekRelative(seconds: Double)
    case seekAbsolute(seconds: Double)
    case adjustVolume(by: Double)
    case setVolume(Double)
    case toggleMute
    case toggleFullScreen
    case close
    /// Loads an external subtitle file and selects it.
    case addSubtitle(fileURL: URL)
    /// Removes the external subtitle currently loaded.
    case removeSubtitles
    /// Selects a subtitle track, or none.
    case selectSubtitle(id: Int?)
    /// Loads one of the video's other audio languages as an external track and selects it.
    case addAudioTrack(url: URL)
    /// Removes the external audio track currently loaded.
    case removeAudioTracks
    /// Selects an audio track by id.
    case selectAudioTrack(id: Int)
    case setSubtitleDelay(seconds: Double)
    case adjustSubtitleDelay(by: Double)
    /// One `sub-*` property, as `SubtitleStyle` produces them.
    case setSubtitleProperty(name: String, value: String)
    case nextChapter
    case previousChapter
    /// Shows the trailing inspector with the chapters page, or hides it when that page is already in front.
    case toggleChaptersInspector
    /// Shows the trailing inspector with the subtitles page, or hides it when that page is already in front.
    case toggleSubtitlesInspector
    /// Shows the trailing inspector with the audio page, or hides it when that page is already in front.
    case toggleAudioInspector
    case toggleMiniPlayer
    /// Resizes the window so the video area has exactly the video's shape, removing the black bars around it.
    case fitWindowToVideo

    /// The mpv command for commands the engine handles; nil for window-level commands.
    public var mpvArguments: [String]? {
        switch self {
        case .togglePause: ["cycle", "pause"]
        case let .seekRelative(seconds): ["seek", "\(seconds)", "relative"]
        case let .seekAbsolute(seconds): ["seek", "\(max(0, seconds))", "absolute"]
        case let .adjustVolume(delta): ["add", "volume", "\(delta)"]
        case let .setVolume(volume): ["set", "volume", "\(min(max(volume, 0), 100))"]
        case .toggleMute: ["cycle", "mute"]
        case let .addSubtitle(fileURL): ["sub-add", fileURL.path, "select"]
        case .removeSubtitles: ["sub-remove"]
        case let .selectSubtitle(id): ["set", "sid", id.map(String.init) ?? "no"]
        // The URL is a signed stream URL with the requester's address in it. It goes to mpv and nowhere else: it is
        // never logged, and never put in a message something else prints.
        case let .addAudioTrack(url): ["audio-add", url.absoluteString, "select"]
        case .removeAudioTracks: ["audio-remove"]
        case let .selectAudioTrack(id): ["set", "aid", String(id)]
        case let .setSubtitleDelay(seconds): ["set", "sub-delay", "\(seconds)"]
        case let .adjustSubtitleDelay(delta): ["add", "sub-delay", "\(delta)"]
        case let .setSubtitleProperty(name, value): ["set", name, value]
        case .toggleFullScreen, .close, .nextChapter, .previousChapter,
             .toggleChaptersInspector, .toggleSubtitlesInspector, .toggleAudioInspector,
             .toggleMiniPlayer, .fitWindowToVideo: nil
        }
    }

    /// Volume and mute act on mpv itself, not on a loaded file, so they are safe to allow with an empty window.
    public var adjustsVolumeOrMute: Bool {
        switch self {
        case .adjustVolume, .setVolume, .toggleMute: true
        default: false
        }
    }
}

/// A key press reduced to what bindings need, so the mapping is testable without AppKit.
public struct KeyPress: Equatable, Sendable {
    public enum Key: Equatable, Sendable {
        case character(String)
        case leftArrow
        case rightArrow
        case upArrow
        case downArrow
    }

    public struct Modifiers: OptionSet, Equatable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
    }

    public var key: Key
    public var modifiers: Modifiers

    public init(_ key: Key, modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

/// IINA-like defaults. Shortcuts with ⌘ (⌘W close, ⌘V paste, ⌃⌘F full screen, ⌘Q quit) live in the main menu, so a
/// binding matches a press only when its modifiers are exactly the ones declared.
public struct KeyBindings: Sendable {
    public static let seekStep = 5.0
    public static let volumeStep = 5.0
    public static let subtitleDelayStep = 0.1

    public static let standard = KeyBindings(bindings: [
        (.character(" "), [], .togglePause),
        (.leftArrow, [], .seekRelative(seconds: -seekStep)),
        (.rightArrow, [], .seekRelative(seconds: seekStep)),
        (.leftArrow, .option, .previousChapter),
        (.rightArrow, .option, .nextChapter),
        (.upArrow, [], .adjustVolume(by: volumeStep)),
        (.downArrow, [], .adjustVolume(by: -volumeStep)),
        (.character("f"), [], .toggleFullScreen),
        (.character("m"), [], .toggleMute),
        (.character("c"), [], .toggleChaptersInspector),
        (.character("s"), [], .toggleSubtitlesInspector),
        (.character("a"), [], .toggleAudioInspector),
        (.character("z"), [], .adjustSubtitleDelay(by: -subtitleDelayStep)),
        (.character("x"), [], .adjustSubtitleDelay(by: subtitleDelayStep)),
    ])

    private let bindings: [(KeyPress.Key, KeyPress.Modifiers, PlayerCommand)]

    public init(bindings: [(KeyPress.Key, KeyPress.Modifiers, PlayerCommand)]) {
        self.bindings = bindings
    }

    public func command(for press: KeyPress) -> PlayerCommand? {
        let key: KeyPress.Key = if case let .character(text) = press.key { .character(text.lowercased()) } else { press.key }
        return bindings.first { $0.0 == key && $0.1 == press.modifiers }?.2
    }
}
