import AppKit
import CueQueue

/// Cue's settings: a small, non-resizable window with one form in it.
///
/// Deliberately the least original surface in the app. Every control here is a stock AppKit one at its system size,
/// laid out in an `NSGridView` with the labels trailing — the shape a Mac user has already met in every other app's
/// settings, so nothing about it has to be learned.
///
/// It owns no state. Each control writes straight to `Preferences` and each reads back from it, so a setting that can
/// also be changed elsewhere — the sidebar's own mode popup, the Queue menu's automatic playback item — has exactly
/// one home, and this window follows along while it is open rather than holding a stale copy.
final class SettingsWindowController: NSWindowController {
    private let preferences: Preferences

    private let appearanceButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let automaticButton = NSButton(checkboxWithTitle: "Play the next video automatically", target: nil, action: nil)
    private let sidebarModeButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sidebarLayoutButton = NSPopUpButton(frame: .zero, pullsDown: false)

    init(preferences: Preferences) {
        self.preferences = preferences
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 220),
            // No `.resizable`: a form with nothing to reflow has no size worth choosing. No `.fullSizeContentView`
            // and no document behaviour either — this is a plain utility window, not another player.
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isRestorable = false
        super.init(window: window)

        window.contentView = makeForm()
        window.center()
        // Everything that writes a preference posts this, including this window's own controls and the reset. Reading
        // it all back on every change is what keeps the two popups in step with the sidebar while both are on screen.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesChanged),
            name: Preferences.didChangeNotification,
            object: nil
        )
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Layout

    private func makeForm() -> NSView {
        appearanceButton.addItems(withTitles: AppearancePreference.allCases.map(\.title))
        appearanceButton.target = self
        appearanceButton.action = #selector(changeAppearance(_:))

        automaticButton.target = self
        automaticButton.action = #selector(changeAutomatic(_:))

        sidebarModeButton.addItems(withTitles: QueueDisplayMode.allCases.map(\.title))
        sidebarModeButton.target = self
        sidebarModeButton.action = #selector(changeSidebarMode(_:))

        sidebarLayoutButton.addItems(withTitles: SidebarLayout.allCases.map(\.title))
        sidebarLayoutButton.target = self
        sidebarLayoutButton.action = #selector(changeSidebarLayout(_:))

        let reset = NSButton(title: "Reset All Settings…", target: self, action: #selector(resetEverything(_:)))
        reset.bezelStyle = .rounded

        let grid = NSGridView(views: [
            [label("Appearance:"), appearanceButton],
            [label("Playback:"), automaticButton],
            [label("Sidebar:"), sidebarModeButton],
            [NSGridCell.emptyContentView, sidebarLayoutButton],
            [NSGridCell.emptyContentView, reset],
        ])
        grid.columnSpacing = 10
        grid.rowSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        // The two sidebar popups are one setting in two parts, so they sit closer together than the rows above, and
        // the reset stands further off from the form it undoes.
        grid.row(at: 3).topPadding = -4
        grid.row(at: 4).topPadding = 12

        let container = NSView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])
        return container
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        return field
    }

    // MARK: - Reading and writing

    /// Puts every control back in step with what is stored. Selecting an item programmatically sends no action, so
    /// this cannot start a round trip back into the store.
    private func refresh() {
        appearanceButton.selectItem(at: AppearancePreference.allCases.firstIndex(of: preferences.appearance) ?? 0)
        automaticButton.state = preferences.playsNextAutomatically ? .on : .off
        let sidebar = preferences.sidebar
        sidebarModeButton.selectItem(at: QueueDisplayMode.allCases.firstIndex(of: sidebar.mode) ?? 0)
        sidebarLayoutButton.selectItem(at: SidebarLayout.allCases.firstIndex(of: sidebar.layout) ?? 0)
    }

    @objc private func preferencesChanged() {
        refresh()
    }

    @objc private func changeAppearance(_ sender: NSPopUpButton) {
        preferences.appearance = choice(AppearancePreference.allCases, from: sender)
    }

    @objc private func changeAutomatic(_ sender: NSButton) {
        preferences.playsNextAutomatically = sender.state == .on
    }

    /// Both sidebar popups write the whole `SidebarSettings` back, read fresh. That keeps the third member —
    /// whether the sidebar is showing, which this window does not offer — exactly as the window left it.
    @objc private func changeSidebarMode(_ sender: NSPopUpButton) {
        var settings = preferences.sidebar
        settings.mode = choice(QueueDisplayMode.allCases, from: sender)
        preferences.sidebar = settings
    }

    @objc private func changeSidebarLayout(_ sender: NSPopUpButton) {
        var settings = preferences.sidebar
        settings.layout = choice(SidebarLayout.allCases, from: sender)
        preferences.sidebar = settings
    }

    /// The case a popup's selection stands for. Clamped rather than trusted: an index out of range would crash, and
    /// the popup's items and the cases are built from the same list anyway.
    private func choice<Value>(_ cases: [Value], from button: NSPopUpButton) -> Value {
        cases[min(max(button.indexOfSelectedItem, 0), cases.count - 1)]
    }

    // MARK: - Reset

    /// Asks first. This throws away settings the owner chose by hand, and it is worth saying out loud what it does
    /// not touch: the fear a button called "reset everything" earns is for the queue, and the queue is safe.
    @objc private func resetEverything(_ sender: Any?) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Reset all settings to their defaults?"
        alert.informativeText = """
            Appearance, automatic playback and the sidebar go back to how Cue starts out. \
            Your queue and where you left off in each video are not touched.
            """
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        // Escape cancels, which is the answer a sheet opened by accident should be one keystroke away from.
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            // Everything that shows a preference is listening, so the window behind this sheet changes appearance and
            // puts its sidebar back as the sheet closes. Nothing here has to be relaunched.
            self?.preferences.reset()
        }
    }
}
