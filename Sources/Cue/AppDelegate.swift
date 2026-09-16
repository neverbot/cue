import AppKit
import CueCore
import CuePlayer
import CueQueue

/// Every delegate callback here already runs on the main thread, and now that this class holds the preferences —
/// a reference type it hands to the two window controllers, which are main-actor bound — saying so is what lets it
/// share them rather than send them.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Overrides the database location, for automated checks that must not touch the real one.
    nonisolated static let databasePathVariable = "CUE_DATABASE_PATH"

    private let arguments: [String]
    private var windowController: PlayerWindowController?
    /// One store for the whole app, shared with the player window and the settings window, so a setting has one home.
    private let preferences = Preferences()
    /// Built the first time the menu item is chosen, and kept afterwards.
    private var settingsWindowController: SettingsWindowController?
    private var aboutWindowController: AboutWindowController?
    /// The queue and the thumbnail cache the player window is using. Held here so the settings window works on the
    /// same two objects rather than opening its own, which is what lets a change made there reach the sidebar now.
    private var store: QueueStore?
    private var thumbnails: ThumbnailStore?
    /// `cue://` links that reached the app before it had a window to give them to. See `PendingLinks`.
    private var pendingLinks = PendingLinks()

    init(arguments: [String]) {
        self.arguments = arguments
    }

    /// The real database, or the override from the environment.
    nonisolated static func databaseURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        guard let path = environment[databasePathVariable], !path.isEmpty else { return QueueDatabase.defaultFileURL }
        return URL(fileURLWithPath: path)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let databaseURL = Self.databaseURL()
        if QueueSmoke.isRequested(in: arguments) {
            QueueSmoke.run(databaseURL: databaseURL)
        }
        // Before any window is built, so the first thing drawn is already in the chosen appearance rather than
        // flickering out of the system one. Re-applied on every change, including a reset.
        applyAppearance()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesChanged),
            name: Preferences.didChangeNotification,
            object: nil
        )
        NSApp.mainMenu = MainMenu.make()
        do {
            let store = QueueStore(database: try QueueDatabase.open(at: databaseURL))
            self.store = store
            // One store for the whole app, for the same reason the preferences are: the settings window's cache
            // section and the sidebar's thumbnails must be looking at one directory and one set of remembered
            // failures, not at two that happen to point at the same path.
            let thumbnails = ThumbnailStore(directory: ThumbnailStore.defaultDirectory)
            self.thumbnails = thumbnails
            let controller = PlayerWindowController(
                engine: try MPVPlaybackEngine(),
                store: store,
                thumbnails: thumbnails,
                // One extractor, so one URLSession and one shared solver cache for the whole app. Wrapped so the
                // queue can warm the next video ahead of playback (see PlayerWindowController).
                resolver: PrefetchingResolver(wrapping: Extractor()),
                resumeStore: DatabaseResumeStore(store: store),
                preferences: preferences
            )
            windowController = controller
            controller.showWindow(nil)
            NSApp.activate()
            if let seconds = SmokeTest.seconds(in: arguments) {
                SmokeTest.run(windowController: controller, playFor: seconds, hidden: SmokeTest.hidesWindow(in: arguments))
            }
            if let input = LaunchInput.parse(arguments: arguments) {
                controller.open(input)
            }
            // Whatever arrived while this was still starting up. A bookmarklet click on a closed Cue lands here:
            // the launch and the link are one gesture, and the link reaches the app before the window does.
            for url in pendingLinks.takeAll() {
                controller.handleAddLink(url)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Cue could not start"
            alert.informativeText = String(describing: error)
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    /// Cue ▸ Settings… (⌘,). The window is a plain one: it takes key focus while it is in front, and gives it back to
    /// the player when it closes, so the player's own key bindings are never in two places at once.
    ///
    /// Nothing to show before the queue is open: a failed launch has already put up its own alert and is on its way
    /// to terminating, and a settings window with no queue behind it could only lie about the cache.
    @objc func showSettings(_ sender: Any?) {
        guard let store, let thumbnails else { return }
        let controller: SettingsWindowController
        if let existing = settingsWindowController {
            controller = existing
        } else {
            controller = SettingsWindowController(preferences: preferences, store: store, thumbnails: thumbnails)
            // The settings window changes the queue the player window is drawing, so the sidebar is told to re-read
            // it rather than being left to catch up at the next launch. An import goes back to the player window's
            // own reading-and-reporting path: one parser and one report, whichever button started it.
            controller.onQueueChange = { [weak self] in self?.windowController?.refreshQueue() }
            controller.onImportFile = { [weak self] url in self?.windowController?.runImport(from: url) }
            settingsWindowController = controller
        }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Cue ▸ About Cue. Kept alive between openings like the settings window, so reopening it does not rebuild the
    /// licence document, and so a second choice of the menu item brings the existing window forward rather than
    /// stacking another one behind it.
    @objc func showAbout(_ sender: Any?) {
        let controller = aboutWindowController ?? AboutWindowController()
        aboutWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Cue ▸ Browser Integration…: writes the bookmarklet page and opens it in the default browser.
    @objc func showBrowserIntegration(_ sender: Any?) {
        BrowserIntegrationPage.open(relativeTo: windowController?.window)
    }

    @objc private func preferencesChanged() {
        applyAppearance()
    }

    /// Nil means "no appearance of our own", which is how an app follows the system — including a switch to dark that
    /// happens while Cue is running. The chrome over the video is not affected by any of this: it draws absolute
    /// colours, because it sits on the picture.
    private func applyAppearance() {
        NSApp.appearance = preferences.appearance.appearanceName.flatMap(NSAppearance.init(named:))
    }

    /// `cue://add?url=…`, from a browser, a bookmarklet or `open`.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let windowController else {
            // Cold launch. macOS delivers the URL as soon as it has launched the app, which is while the database
            // is still opening and libmpv is still starting — there is no window yet. This used to be
            // `windowController?.handleAddLink(url)`, and the optional-chain threw the video away without a
            // sound: Cue opened, looked fine, and had added nothing.
            for url in urls { pendingLinks.hold(url) }
            return
        }
        for url in urls {
            windowController.handleAddLink(url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowController?.shutdown()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

enum MainMenu {
    @MainActor
    static func make() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu("Cue", items: [
            // ⌘, is where macOS keeps settings in every app. Nothing else here claims a comma: every other shortcut
            // in Cue is a letter, plus ⌘0 for fitting the window.
            // First item of the application menu, where macOS has kept it since before Aqua.
            NSMenuItem(title: "About Cue", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: ""),
            .separator(),
            // ⌘, is where macOS keeps settings in every app. Nothing else here claims a comma: every other shortcut
            // in Cue is a letter, plus ⌘0 for fitting the window.
            NSMenuItem(title: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ","),
            // Beside Settings because it is setup, not a queue action: it is done once per browser and then
            // forgotten. No shortcut for the same reason.
            NSMenuItem(
                title: "Browser Integration…",
                action: #selector(AppDelegate.showBrowserIntegration(_:)),
                keyEquivalent: ""
            ),
            .separator(),
            NSMenuItem(title: "Hide Cue", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"),
            .separator(),
            NSMenuItem(title: "Quit Cue", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]))
        menu.addItem(submenu("File", items: [
            NSMenuItem(title: "Import Queue…", action: #selector(PlayerWindowController.importQueue(_:)), keyEquivalent: "i"),
            NSMenuItem(title: "Export Queue…", action: #selector(PlayerWindowController.exportQueue(_:)), keyEquivalent: "e"),
            .separator(),
            NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
        ]))
        menu.addItem(submenu("Edit", items: [
            NSMenuItem(title: "Paste", action: #selector(PlayerWindowController.paste(_:)), keyEquivalent: "v"),
        ]))

        let playNext = NSMenuItem(title: "Play Next in Queue", action: #selector(PlayerWindowController.playNextInQueue(_:)), keyEquivalent: "n")
        playNext.keyEquivalentModifierMask = [.command, .shift]
        let markWatched = NSMenuItem(title: "Mark as Watched", action: #selector(PlayerWindowController.markCurrentWatched(_:)), keyEquivalent: "d")
        markWatched.keyEquivalentModifierMask = [.command, .shift]
        // Checked or unchecked by PlayerWindowController.validateMenuItem(_:).
        let automatic = NSMenuItem(
            title: "Play Next Automatically",
            action: #selector(PlayerWindowController.togglePlaysNextAutomatically(_:)),
            keyEquivalent: ""
        )
        menu.addItem(submenu("Queue", items: [playNext, markWatched, .separator(), automatic]))

        let toggleSidebar = NSMenuItem(title: "Toggle Sidebar", action: #selector(PlayerWindowController.toggleSidebar(_:)), keyEquivalent: "s")
        toggleSidebar.keyEquivalentModifierMask = [.control, .command]
        let cycleMode = NSMenuItem(title: "Next Sidebar Mode", action: #selector(PlayerWindowController.cycleSidebarMode(_:)), keyEquivalent: "m")
        cycleMode.keyEquivalentModifierMask = [.control, .command]
        let toggleLayout = NSMenuItem(title: "Overlay or Push Sidebar", action: #selector(PlayerWindowController.toggleSidebarLayout(_:)), keyEquivalent: "o")
        toggleLayout.keyEquivalentModifierMask = [.control, .command]
        let fullScreen = NSMenuItem(title: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.control, .command]
        let chapters = NSMenuItem(title: "Chapters", action: #selector(PlayerWindowController.toggleChaptersInspector(_:)), keyEquivalent: "c")
        chapters.keyEquivalentModifierMask = [.control, .command]
        let subtitlesItem = NSMenuItem(title: "Subtitles", action: #selector(PlayerWindowController.toggleSubtitlesInspector(_:)), keyEquivalent: "u")
        subtitlesItem.keyEquivalentModifierMask = [.control, .command]
        let audioItem = NSMenuItem(title: "Audio Track", action: #selector(PlayerWindowController.toggleAudioInspector(_:)), keyEquivalent: "a")
        audioItem.keyEquivalentModifierMask = [.control, .command]
        let mini = NSMenuItem(title: "Mini Player", action: #selector(PlayerWindowController.toggleMiniPlayer(_:)), keyEquivalent: "m")
        mini.keyEquivalentModifierMask = [.command, .shift]
        // ⌘0 is the only shortcut here without ⌃ or ⇧ because no other menu item and no bare key binding uses a digit.
        let fitWindow = NSMenuItem(
            title: "Fit Window to Video",
            action: #selector(PlayerWindowController.fitWindowToVideo(_:)),
            keyEquivalent: "0"
        )
        fitWindow.keyEquivalentModifierMask = [.command]
        menu.addItem(submenu("View", items: [
            toggleSidebar, cycleMode, toggleLayout, chapters, subtitlesItem, audioItem, mini, fitWindow,
            .separator(), fullScreen,
        ]))

        let windowMenu = submenu("Window", items: [
            NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
        ])
        menu.addItem(windowMenu)
        NSApp.windowsMenu = windowMenu.submenu
        return menu
    }

    @MainActor
    private static func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        items.forEach(submenu.addItem)
        item.submenu = submenu
        return item
    }
}
