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

    /// The mpv command for commands the engine handles; nil for window-level commands.
    public var mpvArguments: [String]? {
        switch self {
        case .togglePause: ["cycle", "pause"]
        case let .seekRelative(seconds): ["seek", "\(seconds)", "relative"]
        case let .seekAbsolute(seconds): ["seek", "\(max(0, seconds))", "absolute"]
        case let .adjustVolume(delta): ["add", "volume", "\(delta)"]
        case let .setVolume(volume): ["set", "volume", "\(min(max(volume, 0), 100))"]
        case .toggleMute: ["cycle", "mute"]
        case .toggleFullScreen, .close: nil
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

/// IINA-like defaults. Shortcuts with ⌘ (⌘W close, ⌘V paste, ⌃⌘F full screen, ⌘Q quit) live in the main menu, so
/// bindings only match unmodified keys and leave everything else to the responder chain.
public struct KeyBindings: Sendable {
    public static let seekStep = 5.0
    public static let volumeStep = 5.0

    public static let standard = KeyBindings(bindings: [
        (.character(" "), .togglePause),
        (.leftArrow, .seekRelative(seconds: -seekStep)),
        (.rightArrow, .seekRelative(seconds: seekStep)),
        (.upArrow, .adjustVolume(by: volumeStep)),
        (.downArrow, .adjustVolume(by: -volumeStep)),
        (.character("f"), .toggleFullScreen),
        (.character("m"), .toggleMute),
    ])

    private let bindings: [(KeyPress.Key, PlayerCommand)]

    public init(bindings: [(KeyPress.Key, PlayerCommand)]) {
        self.bindings = bindings
    }

    public func command(for press: KeyPress) -> PlayerCommand? {
        guard press.modifiers.isEmpty else { return nil }
        let key: KeyPress.Key = if case let .character(text) = press.key { .character(text.lowercased()) } else { press.key }
        return bindings.first { $0.0 == key }?.1
    }
}
