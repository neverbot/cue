import AppKit
import CueCore
import CuePlayer
import CueQueue

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Overrides the database location, for automated checks that must not touch the real one.
    static let databasePathVariable = "CUE_DATABASE_PATH"

    private let arguments: [String]
    private var windowController: PlayerWindowController?

    init(arguments: [String]) {
        self.arguments = arguments
    }

    /// The real database, or the override from the environment.
    static func databaseURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        guard let path = environment[databasePathVariable], !path.isEmpty else { return QueueDatabase.defaultFileURL }
        return URL(fileURLWithPath: path)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let databaseURL = Self.databaseURL()
        if QueueSmoke.isRequested(in: arguments) {
            QueueSmoke.run(databaseURL: databaseURL)
        }
        NSApp.mainMenu = MainMenu.make()
        do {
            let store = QueueStore(database: try QueueDatabase.open(at: databaseURL))
            // One-time move of the player's JSON positions into the database. The file is left where it is.
            try JSONResumeImport(store: store).runIfNeeded(from: JSONResumeStore.defaultFileURL)

            let controller = PlayerWindowController(
                engine: try MPVPlaybackEngine(),
                store: store,
                thumbnails: ThumbnailStore(directory: ThumbnailStore.defaultDirectory),
                // One extractor, so one URLSession and one shared solver cache for the whole app. Wrapped so the
                // queue can warm the next video ahead of playback (see PlayerWindowController).
                resolver: PrefetchingResolver(wrapping: Extractor()),
                resumeStore: DatabaseResumeStore(store: store)
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
        } catch {
            let alert = NSAlert()
            alert.messageText = "Cue could not start"
            alert.informativeText = String(describing: error)
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    /// `cue://add?url=…`, from a browser, a bookmarklet or `open`.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            windowController?.handleAddLink(url)
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
        let chapters = NSMenuItem(title: "Chapters", action: #selector(PlayerWindowController.toggleChaptersPanel(_:)), keyEquivalent: "c")
        chapters.keyEquivalentModifierMask = [.control, .command]
        let subtitlesItem = NSMenuItem(title: "Subtitles", action: #selector(PlayerWindowController.toggleSubtitlesPanel(_:)), keyEquivalent: "u")
        subtitlesItem.keyEquivalentModifierMask = [.control, .command]
        menu.addItem(submenu("View", items: [toggleSidebar, cycleMode, toggleLayout, chapters, subtitlesItem, .separator(), fullScreen]))

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
