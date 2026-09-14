import Foundation

/// Somewhere preferences are read from and written to. `UserDefaults` is the only one the app ever uses — preferences
/// are local to this machine and go nowhere else — and tests pass their own, so a test run never reads or writes the
/// owner's real defaults.
public protocol PreferenceStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: PreferenceStore {}

/// Every defaults key Cue owns, in one place, so none of them is a string literal loose in a view controller. A
/// settings window that offers to restore defaults resets exactly this list: a key that is not here does not exist,
/// and cannot be quietly left behind by a reset.
public enum PreferenceKey: String, CaseIterable, Sendable {
    case appearance = "appearance"
    case playsNextAutomatically = "playback.plays-next-automatically"
    case sidebarMode = "sidebar.mode"
    case sidebarLayout = "sidebar.layout"
    case sidebarVisible = "sidebar.visible"
    case inspectorVisible = "inspector.visible"
    case inspectorTab = "inspector.tab"
}

/// How the sidebar looked when the app was last used.
public struct SidebarSettings: Equatable, Sendable {
    public var mode: QueueDisplayMode
    public var layout: SidebarLayout
    public var isVisible: Bool

    /// What a first launch gets, and what anything unreadable falls back to.
    public static let standard = SidebarSettings(mode: .list, layout: .push, isVisible: true)

    public init(mode: QueueDisplayMode, layout: SidebarLayout, isVisible: Bool) {
        self.mode = mode
        self.layout = layout
        self.isVisible = isVisible
    }
}

/// How the trailing inspector was left when the app was last used.
public struct InspectorSettings: Equatable, Sendable {
    public var tab: InspectorTab
    public var isVisible: Bool

    /// What a first launch gets, and what anything unreadable falls back to. Closed: the picture owns the window
    /// until the chapters or the subtitles are actually asked for.
    public static let standard = InspectorSettings(tab: .chapters, isVisible: false)

    public init(tab: InspectorTab, isVisible: Bool) {
        self.tab = tab
        self.isVisible = isVisible
    }
}

/// Reads and writes the app's preferences.
///
/// Reading never fails. A key that was never written, one holding a value of the wrong type, and one holding a name
/// this build no longer knows all fall back to the default, so a defaults domain left behind by an older version — or
/// edited by hand — cannot crash the app or restore the sidebar into a state it has no way to draw.
public final class Preferences {
    private let store: any PreferenceStore

    public init(store: any PreferenceStore = UserDefaults.standard) {
        self.store = store
    }

    /// Posted after anything here is written, including a reset, so that every part of the app showing a preference
    /// catches up at once. There is one copy of each setting — this store — and both the settings window and the
    /// controls that also change it (the sidebar's own popup, the Queue menu) read it back from here rather than
    /// keeping a second copy in step by hand.
    public static let didChangeNotification = Notification.Name("com.neverbot.cue.preferences-did-change")

    /// Whether the sidebar, the panels and the settings window follow the system, or are pinned light or dark.
    public var appearance: AppearancePreference {
        get { value(.appearance, fallingBackTo: AppearancePreference.standard) }
        set {
            store.set(newValue.rawValue, forKey: PreferenceKey.appearance.rawValue)
            announceChange()
        }
    }

    /// Whether finishing a video starts the next one. The queue coordinator holds this while the app runs; this is
    /// where it survives a quit.
    public var playsNextAutomatically: Bool {
        get {
            // A bool is stored as a bool: anything else is not a value this can use.
            store.object(forKey: PreferenceKey.playsNextAutomatically.rawValue) as? Bool ?? Self.playsNextAutomaticallyByDefault
        }
        set {
            store.set(newValue, forKey: PreferenceKey.playsNextAutomatically.rawValue)
            announceChange()
        }
    }

    /// Working through a queue is the point of the app, so it moves on by itself until told otherwise.
    public static let playsNextAutomaticallyByDefault = true

    /// The sidebar's appearance. Read once at startup; written whenever one of the three changes.
    public var sidebar: SidebarSettings {
        get {
            SidebarSettings(
                mode: value(.sidebarMode, fallingBackTo: SidebarSettings.standard.mode),
                layout: value(.sidebarLayout, fallingBackTo: SidebarSettings.standard.layout),
                // A bool is stored as a bool: anything else — a string, an array — is not a value this can use.
                isVisible: store.object(forKey: PreferenceKey.sidebarVisible.rawValue) as? Bool
                    ?? SidebarSettings.standard.isVisible
            )
        }
        set {
            store.set(newValue.mode.rawValue, forKey: PreferenceKey.sidebarMode.rawValue)
            store.set(newValue.layout.rawValue, forKey: PreferenceKey.sidebarLayout.rawValue)
            store.set(newValue.isVisible, forKey: PreferenceKey.sidebarVisible.rawValue)
            announceChange()
        }
    }

    /// The inspector's appearance: whether it is open, and which of its two pages was last in front. Read once at
    /// startup; written whenever either changes.
    public var inspector: InspectorSettings {
        get {
            InspectorSettings(
                tab: value(.inspectorTab, fallingBackTo: InspectorSettings.standard.tab),
                // A bool is stored as a bool: anything else — a string, an array — is not a value this can use.
                isVisible: store.object(forKey: PreferenceKey.inspectorVisible.rawValue) as? Bool
                    ?? InspectorSettings.standard.isVisible
            )
        }
        set {
            store.set(newValue.tab.rawValue, forKey: PreferenceKey.inspectorTab.rawValue)
            store.set(newValue.isVisible, forKey: PreferenceKey.inspectorVisible.rawValue)
            announceChange()
        }
    }

    /// Forgets every key Cue owns, so the next read returns the defaults. This is what a settings window's "restore
    /// defaults" calls, and why the keys are enumerated rather than scattered.
    public func reset() {
        for key in PreferenceKey.allCases {
            store.removeObject(forKey: key.rawValue)
        }
        announceChange()
    }

    /// Tells whoever is showing a preference that it changed. Posted after the write, never before, so an observer
    /// that reads straight back gets the new value.
    private func announceChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    /// One stored enum, or the default. A value that is not a string, or is a string the enum does not recognise,
    /// falls back rather than being guessed at: an unknown name is a value from some other version of this app.
    private func value<Value: RawRepresentable>(
        _ key: PreferenceKey,
        fallingBackTo fallback: Value
    ) -> Value where Value.RawValue == String {
        guard let raw = store.object(forKey: key.rawValue) as? String else { return fallback }
        return Value(rawValue: raw) ?? fallback
    }
}
