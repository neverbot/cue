import AppKit
import CueCore
import CueQueue

/// Cue's settings: a small, non-resizable window with one form in it.
///
/// Deliberately the least original surface in the app. Every control here is a stock AppKit one at its system size,
/// and the form is one column of labelled sections — the shape a Mac user has already met in every other app's
/// settings, so nothing about it has to be learned. Not a tabbed window: five short groups do not need five screens,
/// and a tab bar would hide four of them behind a click.
///
/// It owns no preference state. Each control writes straight to `Preferences` and each reads back from it, so a
/// setting that can also be changed elsewhere — the sidebar's own mode popup, the Queue menu's automatic playback
/// item — has exactly one home, and this window follows along while it is open rather than holding a stale copy.
///
/// It does not own the queue or the thumbnail cache either: both are the same objects the player window uses, so a
/// change made here shows up in the sidebar at once instead of at the next launch.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let preferences: Preferences
    private let store: QueueStore
    private let thumbnails: ThumbnailStore

    private let appearanceButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let automaticButton = NSButton(checkboxWithTitle: "Play the next video automatically", target: nil, action: nil)
    private let sidebarModeButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sidebarLayoutButton = NSPopUpButton(frame: .zero, pullsDown: false)

    // MARK: - Cache

    private let cacheSizeLabel = NSTextField(labelWithString: CachePresentation.measuringText)
    private let cacheStatusLabel = NSTextField(labelWithString: "")
    private let emptyCacheButton = NSButton(title: "Empty Cache", target: nil, action: nil)
    private let refetchButton = NSButton(title: "Re-fetch Thumbnails", target: nil, action: nil)
    private let stopRefetchButton = NSButton(title: "Stop", target: nil, action: nil)
    /// Measures the cache directory. Cancelled when a newer measurement starts, so a slow walk cannot overwrite the
    /// answer to a later question.
    private var measureTask: Task<Void, Never>?
    /// The running re-fetch, or nil. Also the flag that says one is running: there is never more than one.
    private var refetchTask: Task<Void, Never>?

    init(preferences: Preferences, store: QueueStore, thumbnails: ThumbnailStore) {
        self.preferences = preferences
        self.store = store
        self.thumbnails = thumbnails
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            // No `.resizable`: a form with nothing to reflow has no size worth choosing. No `.fullSizeContentView`
            // and no document behaviour either — this is a plain utility window, not another player.
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isRestorable = false
        super.init(window: window)

        let form = makeForm()
        window.contentView = form
        // The form decides how big the window is, rather than a guessed content rect deciding how much of the form
        // fits. Nothing here reflows, so the size settled here is the size for good.
        window.setContentSize(form.fittingSize)
        window.center()
        window.delegate = self
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

        let form = NSStackView(views: [
            section("Appearance", [row([appearanceButton])]),
            section("Playback", [row([automaticButton])]),
            section("Sidebar", [row([sidebarModeButton, sidebarLayoutButton])]),
            cacheSection(),
            row([reset]),
        ])
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 18
        // The reset stands further off from the form it undoes than the sections stand from each other.
        if let last = form.arrangedSubviews.dropLast().last {
            form.setCustomSpacing(26, after: last)
        }

        let container = NSView()
        form.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(form)
        NSLayoutConstraint.activate([
            form.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            form.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            form.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            form.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            // Wide enough that the widest button row is not what decides the window's width, so a status line
            // appearing under it does not make the form look ragged.
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 460),
        ])
        return container
    }

    private func cacheSection() -> NSView {
        cacheSizeLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        emptyCacheButton.target = self
        emptyCacheButton.action = #selector(emptyCache(_:))
        emptyCacheButton.bezelStyle = .rounded

        refetchButton.target = self
        refetchButton.action = #selector(refetchThumbnails(_:))
        refetchButton.bezelStyle = .rounded

        stopRefetchButton.target = self
        stopRefetchButton.action = #selector(stopRefetch(_:))
        stopRefetchButton.bezelStyle = .rounded
        // Present but greyed while nothing is running, rather than appearing and disappearing: a control that comes
        // and goes moves the row it is in, and this window never moves.
        stopRefetchButton.isEnabled = false

        return section("Cache", [
            row([NSTextField(labelWithString: "Thumbnails:"), cacheSizeLabel]),
            row([emptyCacheButton, refetchButton, stopRefetchButton]),
            statusLabel(cacheStatusLabel),
        ])
    }

    /// One labelled group: a heading, and its controls indented under it.
    private func section(_ title: String, _ rows: [NSView]) -> NSView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

        let content = NSStackView(views: rows)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        // Indenting through the stack's own insets rather than a second leading constraint, which would fight the
        // alignment the stack already applies to everything it arranges.
        content.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)

        let group = NSStackView(views: [heading, content])
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 6
        return group
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    /// A line that reports what just happened. Secondary, single line, and the first thing allowed to truncate, so a
    /// long sentence never widens a window whose size was settled before it was written.
    private func statusLabel(_ field: NSTextField) -> NSTextField {
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = .secondaryLabelColor
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        refresh()
        // The cache is a number about the world, not a setting, so it is asked again every time the window comes up
        // rather than trusted from the last time it was open.
        measureCache()
    }

    /// Nothing here outlives the window it reports into. A re-fetch reaches YouTube once per video, and a window that
    /// has been closed is no longer a reason to keep asking.
    func windowWillClose(_ notification: Notification) {
        refetchTask?.cancel()
        measureTask?.cancel()
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

    // MARK: - Cache

    /// Adds up the cache directory away from the main thread and shows the answer when it arrives.
    ///
    /// `ThumbnailStore` is an actor, so the `await` leaves the main actor and the file walk happens on the actor's own
    /// executor: the window stays live through it, however many files are in there. Until the answer comes back the
    /// row says so in words, because a blank row reads as a broken one.
    private func measureCache() {
        measureTask?.cancel()
        cacheSizeLabel.stringValue = CachePresentation.measuringText
        measureTask = Task { [weak self, thumbnails] in
            let bytes = await thumbnails.cachedByteCount()
            guard !Task.isCancelled, let self else { return }
            self.cacheSizeLabel.stringValue = CachePresentation.sizeText(bytes: bytes)
        }
    }

    /// No sheet asks first. The images cost nothing to lose and come back on their own, so the honest thing is to do
    /// it and say what it freed — a confirmation would be asking permission for nothing.
    @objc private func emptyCache(_ sender: Any?) {
        emptyCacheButton.isEnabled = false
        Task { [weak self, thumbnails] in
            let freed = await thumbnails.empty()
            guard let self else { return }
            self.emptyCacheButton.isEnabled = true
            self.cacheStatusLabel.stringValue = CachePresentation.freedText(bytes: freed)
            self.measureCache()
        }
    }

    /// Fetches every queued video's thumbnail again, one at a time.
    ///
    /// Strictly sequential: each request is awaited to the end before the next one begins, so a queue of hundreds is
    /// hundreds of requests spread out rather than hundreds at once. Every hop is an `await`, so the window stays
    /// live throughout and the count on screen moves as the work lands. A video whose image cannot be fetched is
    /// counted and passed over: one dead video must not stop the rest of the queue.
    @objc private func refetchThumbnails(_ sender: Any?) {
        guard refetchTask == nil else { return }
        let videoIDs = ((try? store.videos()) ?? []).compactMap(\.video)
        guard !videoIDs.isEmpty else {
            cacheStatusLabel.stringValue = "There are no videos in the queue to fetch thumbnails for."
            return
        }
        setRefetching(true)
        cacheStatusLabel.stringValue = CachePresentation.progressText(completed: 0, total: videoIDs.count)
        refetchTask = Task { [weak self, thumbnails] in
            var completed = 0
            for videoID in videoIDs {
                guard !Task.isCancelled else { break }
                _ = try? await thumbnails.refreshedImageData(for: videoID)
                completed += 1
                guard let self else { return }
                self.cacheStatusLabel.stringValue = CachePresentation.progressText(
                    completed: completed, total: videoIDs.count
                )
            }
            let cancelled = Task.isCancelled
            guard let self else { return }
            self.refetchTask = nil
            self.setRefetching(false)
            self.cacheStatusLabel.stringValue = CachePresentation.refetchedText(
                completed: completed, total: videoIDs.count, cancelled: cancelled
            )
            self.measureCache()
        }
    }

    @objc private func stopRefetch(_ sender: Any?) {
        refetchTask?.cancel()
    }

    /// While a re-fetch runs, the two buttons that would interfere with it are greyed and Stop is the only one live.
    private func setRefetching(_ running: Bool) {
        refetchButton.isEnabled = !running
        emptyCacheButton.isEnabled = !running
        stopRefetchButton.isEnabled = running
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
