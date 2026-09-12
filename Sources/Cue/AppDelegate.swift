import AppKit
import CuePlayer

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let arguments: [String]
    private var windowController: PlayerWindowController?

    init(arguments: [String]) {
        self.arguments = arguments
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        do {
            let controller = PlayerWindowController(engine: try MPVPlaybackEngine())
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
            alert.messageText = "Cue could not start its player"
            alert.informativeText = String(describing: error)
            alert.runModal()
            NSApp.terminate(nil)
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
            NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
        ]))
        menu.addItem(submenu("Edit", items: [
            NSMenuItem(title: "Paste", action: #selector(PlayerWindowController.paste(_:)), keyEquivalent: "v"),
        ]))
        let fullScreen = NSMenuItem(title: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.control, .command]
        menu.addItem(submenu("View", items: [fullScreen]))
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
