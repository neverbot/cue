import AppKit

/// Which appearance Cue's own surfaces take: the sidebar, the panels and the settings window.
///
/// It does not govern the chrome drawn over the video. That sits on the picture, which is dark at every system
/// setting, so `ChromeStyle` stays absolute on purpose and never consults this.
public enum AppearancePreference: String, CaseIterable, Sendable {
    /// Whatever the system is doing, now and whenever it changes.
    case system
    case light
    case dark

    /// What a first launch gets, and what anything unreadable falls back to.
    public static let standard = AppearancePreference.system

    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The appearance to hand `NSApplication.appearance`, or nil to override nothing.
    ///
    /// Nil is not the same as naming the light appearance: an app with no appearance of its own keeps following the
    /// system, including a switch to dark at sunset that happens while Cue is running.
    public var appearanceName: NSAppearance.Name? {
        switch self {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
}
