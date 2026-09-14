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

    @Test func givesEveryKeyADistinctName() {
        // Two keys sharing a name would silently overwrite each other, and a reset would appear to miss one.
        let names = PreferenceKey.allCases.map(\.rawValue)
        #expect(Set(names).count == names.count)
    }
}
