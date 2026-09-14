import AppKit
@testable import CueQueue
import Foundation
import Testing

/// A preference store that lives only as long as the test. The real one is `UserDefaults`, and a test run must not
/// read or write the preferences of the machine it runs on.
private final class MemoryPreferenceStore: PreferenceStore {
    var values: [String: Any] = [:]

    func object(forKey key: String) -> Any? { values[key] }

    func set(_ value: Any?, forKey key: String) { values[key] = value }

    func removeObject(forKey key: String) { values[key] = nil }
}

@Suite struct PreferencesTests {
    @Test func usesTheDefaultsWhenNothingWasEverStored() {
        let preferences = Preferences(store: MemoryPreferenceStore())
        #expect(preferences.sidebar == SidebarSettings.standard)
        #expect(preferences.sidebar.mode == .list)
        #expect(preferences.sidebar.layout == .push)
        #expect(preferences.sidebar.isVisible)
    }

    @Test func restoresWhatWasStored() {
        let store = MemoryPreferenceStore()
        let written = SidebarSettings(mode: .thumbnail, layout: .overlay, isVisible: false)
        Preferences(store: store).sidebar = written
        // A second instance, as if the app had quit and come back: nothing is carried in memory.
        #expect(Preferences(store: store).sidebar == written)
    }

    @Test func restoresEveryModeAndLayoutItCouldHaveBeenLeftIn() {
        for mode in QueueDisplayMode.allCases {
            for layout in SidebarLayout.allCases {
                let store = MemoryPreferenceStore()
                Preferences(store: store).sidebar = SidebarSettings(mode: mode, layout: layout, isVisible: true)
                #expect(Preferences(store: store).sidebar.mode == mode)
                #expect(Preferences(store: store).sidebar.layout == layout)
            }
        }
    }

    @Test func remembersTheSidebarBeingHidden() {
        // Worth its own check: `false` is also what an absent key reads as, so only a round trip proves it was stored.
        let store = MemoryPreferenceStore()
        Preferences(store: store).sidebar = SidebarSettings(mode: .list, layout: .push, isVisible: false)
        #expect(Preferences(store: store).sidebar.isVisible == false)
    }

    @Test func fallsBackWhenTheStoredNameIsNotOneThisBuildKnows() {
        // What an older or newer version of the app would leave behind.
        let store = MemoryPreferenceStore()
        store.values[PreferenceKey.sidebarMode.rawValue] = "mosaic"
        store.values[PreferenceKey.sidebarLayout.rawValue] = "beside"
        #expect(Preferences(store: store).sidebar.mode == .list)
        #expect(Preferences(store: store).sidebar.layout == .push)
    }

    @Test func fallsBackWhenTheStoredValueIsTheWrongTypeAltogether() {
        let store = MemoryPreferenceStore()
        store.values[PreferenceKey.sidebarMode.rawValue] = 7
        store.values[PreferenceKey.sidebarLayout.rawValue] = ["push"]
        store.values[PreferenceKey.sidebarVisible.rawValue] = "no"
        #expect(Preferences(store: store).sidebar == SidebarSettings.standard)
    }

    @Test func fallsBackForOneUnreadableValueWithoutLosingTheOthers() {
        let store = MemoryPreferenceStore()
        Preferences(store: store).sidebar = SidebarSettings(mode: .compact, layout: .overlay, isVisible: false)
        store.values[PreferenceKey.sidebarMode.rawValue] = "mosaic"
        let restored = Preferences(store: store).sidebar
        #expect(restored.mode == .list)
        #expect(restored.layout == .overlay)
        #expect(restored.isVisible == false)
    }

    @Test func resetForgetsEveryKeyItOwns() {
        let store = MemoryPreferenceStore()
        let preferences = Preferences(store: store)
        preferences.sidebar = SidebarSettings(mode: .compact, layout: .overlay, isVisible: false)
        preferences.reset()
        #expect(preferences.sidebar == SidebarSettings.standard)
        // Nothing of ours is left behind: a settings window's "restore defaults" has to clear the domain, not mask it.
        #expect(store.values.isEmpty)
    }

    @Test func keepsTheInspectorClosedUntilItIsAskedFor() {
        let preferences = Preferences(store: MemoryPreferenceStore())
        #expect(preferences.inspector == InspectorSettings.standard)
        #expect(preferences.inspector.isVisible == false)
        #expect(preferences.inspector.tab == .chapters)
    }

    @Test func restoresTheInspectorPageItWasLeftShowing() {
        for tab in InspectorTab.allCases {
            let store = MemoryPreferenceStore()
            Preferences(store: store).inspector = InspectorSettings(tab: tab, isVisible: true)
            // A second instance, as if the app had quit and come back: nothing is carried in memory.
            #expect(Preferences(store: store).inspector == InspectorSettings(tab: tab, isVisible: true))
        }
    }

    @Test func fallsBackWhenTheStoredInspectorPageIsNotOneThisBuildKnows() {
        // What an older or newer version of the app would leave behind.
        let store = MemoryPreferenceStore()
        store.values[PreferenceKey.inspectorTab.rawValue] = "comments"
        store.values[PreferenceKey.inspectorVisible.rawValue] = true
        let restored = Preferences(store: store).inspector
        #expect(restored.tab == .chapters)
        // One unreadable value does not lose the other.
        #expect(restored.isVisible)
    }

    @Test func fallsBackWhenTheStoredInspectorValueIsTheWrongTypeAltogether() {
        let store = MemoryPreferenceStore()
        store.values[PreferenceKey.inspectorTab.rawValue] = 4
        store.values[PreferenceKey.inspectorVisible.rawValue] = "yes"
        #expect(Preferences(store: store).inspector == InspectorSettings.standard)
    }

    @Test func remembersTheInspectorBeingOpen() {
        // Worth its own check: `true` is not what an absent key reads as, so only a round trip proves it was stored.
        let store = MemoryPreferenceStore()
        Preferences(store: store).inspector = InspectorSettings(tab: .subtitles, isVisible: true)
        #expect(Preferences(store: store).inspector.isVisible)
    }

    @Test func followsTheSystemAppearanceUntilOneIsChosen() {
        #expect(Preferences(store: MemoryPreferenceStore()).appearance == .system)
        #expect(AppearancePreference.standard == .system)
    }

    @Test func restoresEveryAppearanceItCouldHaveBeenLeftIn() {
        for appearance in AppearancePreference.allCases {
            let store = MemoryPreferenceStore()
            Preferences(store: store).appearance = appearance
            // A second instance, as if the app had quit and come back.
            #expect(Preferences(store: store).appearance == appearance)
        }
    }

    @Test func fallsBackToTheSystemAppearanceWhenTheStoredNameIsNotOneThisBuildKnows() {
        let store = MemoryPreferenceStore()
        store.values[PreferenceKey.appearance.rawValue] = "sepia"
        #expect(Preferences(store: store).appearance == .system)
    }

    @Test func fallsBackToTheSystemAppearanceWhenTheStoredValueIsTheWrongTypeAltogether() {
        let store = MemoryPreferenceStore()
        store.values[PreferenceKey.appearance.rawValue] = 3
        #expect(Preferences(store: store).appearance == .system)
    }

    @Test func mapsEachAppearanceToTheOneTheSystemKnowsByThatName() {
        // Following the system is an absent appearance, not the light one: an app that names `aqua` stops following a
        // switch to dark that happens while it runs.
        #expect(AppearancePreference.system.appearanceName == nil)
        #expect(AppearancePreference.light.appearanceName == .aqua)
        #expect(AppearancePreference.dark.appearanceName == .darkAqua)
    }

    @Test func playsTheNextVideoAutomaticallyUntilItIsTurnedOff() {
        #expect(Preferences(store: MemoryPreferenceStore()).playsNextAutomatically)
    }

    @Test func remembersTheNextVideoNotPlayingAutomatically() {
        // Worth a round trip: `false` is also what an absent key would read as under a different default.
        let store = MemoryPreferenceStore()
        Preferences(store: store).playsNextAutomatically = false
        #expect(Preferences(store: store).playsNextAutomatically == false)
    }

    @Test func fallsBackToPlayingTheNextVideoWhenTheStoredValueIsTheWrongTypeAltogether() {
        let store = MemoryPreferenceStore()
        store.values[PreferenceKey.playsNextAutomatically.rawValue] = "off"
        #expect(Preferences(store: store).playsNextAutomatically)
    }

    @Test func resetReturnsEveryStoredSettingToItsDefault() {
        // The whole promise of the reset button: a key that a reset left behind would make it a lie.
        let store = MemoryPreferenceStore()
        let preferences = Preferences(store: store)
        preferences.appearance = .dark
        preferences.playsNextAutomatically = false
        preferences.sidebar = SidebarSettings(mode: .compact, layout: .overlay, isVisible: false)
        preferences.inspector = InspectorSettings(tab: .subtitles, isVisible: true)
        preferences.reset()
        #expect(preferences.appearance == .system)
        #expect(preferences.playsNextAutomatically)
        #expect(preferences.sidebar == SidebarSettings.standard)
        #expect(preferences.inspector == InspectorSettings.standard)
        #expect(store.values.isEmpty)
    }

    @Test func givesEveryKeyADistinctName() {
        // Two keys sharing a name would silently overwrite each other, and a reset would appear to miss one.
        let names = PreferenceKey.allCases.map(\.rawValue)
        #expect(Set(names).count == names.count)
    }
}
