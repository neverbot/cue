import AppKit
import CueCore
import CueMPV
import CuePlayer
import CueQueue
import os

/// One player window: a split view with the queue sidebar beside (or over) the video. Owns the engine, the player
/// controller, the queue coordinator and the video layer, and enforces the shutdown order
/// (controller → render context → mpv core).
final class PlayerWindowController: NSWindowController, NSWindowDelegate {
    let engine: MPVPlaybackEngine
    let controller: PlayerController
    let coordinator: QueueCoordinator

    private let store: QueueStore
    /// Where the sidebar's appearance is remembered between launches.
    private let preferences: Preferences
    private let playerView: PlayerView
    /// The container the player view normally lives in; where it returns when the mini player closes.
    private let playerContainer: NSView
    /// Shows and hides the sidebar, so the menu is not the only way.
    private let sidebarButton = PlayerWindowController.sidebarToggleButton()
    /// Carries the toggle in the title bar, where AppKit places it after the traffic lights using the system's own
    /// spacing. Nothing here measures that spacing, which is the point: it is not ours to guess.
    private let sidebarAccessory = NSTitlebarAccessoryViewController()
    /// What the chrome last reported, so a full screen transition can put the title bar back where the chrome is
    /// rather than where the last fade left it.
    private var chromeIsVisible = true
    private let sidebar: QueueSidebarViewController
    private let sidebarHost: SidebarHost
    private let splitViewController: NSSplitViewController
    private let sidebarItem: NSSplitViewItem
    private var fittedVideoSize: VideoSize?
    /// The width the pushed sidebar last took on screen. A collapsed split item reports nothing, so the width it is
    /// about to take again has to be remembered from when it was visible.
    private var lastSidebarWidth: CGFloat = QueueSidebarViewController.width
    /// The chapters of whatever is playing, rebuilt when the stream changes.
    private var timeline = ChapterTimeline(chapters: [], duration: nil)
    /// Storyboard sheets for the video playing now. Recreated per video so nothing survives into the next one.
    private var storyboards: StoryboardStore?
    /// Rises with every hover, so a sheet that arrives late for a position the pointer has left is dropped.
    private var previewToken = 0
    private var loggedDecodingFor: URL?
    private var isShutDown = false
    private let logger = Logger(subsystem: "com.neverbot.cue", category: "player")

    private var subtitles = SubtitleSession()
    /// Cues already downloaded for the video playing now, by track id.
    private var loadedCues: [String: [CaptionCue]] = [:]
    private let captions = CaptionLoader()

    private lazy var chaptersPanel: ChaptersPanelController = {
        let panel = ChaptersPanelController()
        panel.onSelect = { [weak self] seconds in self?.controller.perform(.seekAbsolute(seconds: seconds)) }
        return panel
    }()

    private lazy var subtitlesPanel: SubtitlesPanelController = {
        let panel = SubtitlesPanelController()
        panel.onSelect = { [weak self] track in self?.chooseSubtitle(track) }
        panel.onStyleChange = { [weak self] style in self?.send(self?.subtitles.apply(style) ?? []) }
        panel.onDelayChange = { [weak self] delay in self?.send(self?.subtitles.setDelay(delay) ?? []) }
        panel.onExport = { [weak self] format in self?.exportSubtitle(as: format) }
        return panel
    }()

    private var miniPlayer: MiniPlayerWindowController?
    private var miniPlayerCorner = MiniPlayerGeometry.Corner.bottomRight

    init(
        engine: MPVPlaybackEngine,
        store: QueueStore,
        thumbnails: ThumbnailStore,
        resolver: any StreamResolving,
        resumeStore: any ResumeStore,
        preferences: Preferences = Preferences()
    ) {
        self.engine = engine
        self.store = store
        self.preferences = preferences
        // Read once, here. Everything after this works from the live sidebar, and each change writes straight back,
        // so nothing has to be polled or re-read.
        let settings = preferences.sidebar
        controller = PlayerController(engine: engine, resolver: resolver, resumeStore: resumeStore)
        // Only a resolver that also does prefetching (PrefetchingResolver, in production) drives it; a bare
        // resolver leaves the queue's behaviour exactly as it was before prefetching existed.
        coordinator = QueueCoordinator(store: store, player: controller, prefetcher: resolver as? any StreamPrefetching)
        playerView = PlayerView(handle: engine.handle)
        sidebar = QueueSidebarViewController(store: store, thumbnails: thumbnails, mode: settings.mode)

        // The video fills its own view controller; the overlay sidebar floats in the same view, above it.
        let playerContainer = NSView(frame: NSRect(origin: .zero, size: WindowGeometry.defaultContentSize))
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerContainer.addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: playerContainer.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: playerContainer.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: playerContainer.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: playerContainer.bottomAnchor),
        ])
        self.playerContainer = playerContainer
        let playerViewController = NSViewController()
        playerViewController.view = playerContainer

        let sidebarContainer = NSViewController()
        sidebarContainer.view = NSView()
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarContainer)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 420
        sidebarItem.canCollapse = true
        sidebarItem.holdingPriority = .defaultLow

        splitViewController = NSSplitViewController()
        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(NSSplitViewItem(viewController: playerViewController))

        sidebarHost = SidebarHost(
            sidebar: sidebar,
            splitItem: sidebarItem,
            overlayContainer: playerContainer,
            parent: playerViewController,
            layout: settings.layout,
            isVisible: settings.isVisible
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: WindowGeometry.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Cue"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.isMovableByWindowBackground = true
        window.isRestorable = false
        window.backgroundColor = .black
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentMinSize = NSSize(width: 320, height: 180)
        window.contentViewController = splitViewController
        window.center()
        super.init(window: window)

        window.delegate = self
        window.makeFirstResponder(playerView)
        playerView.onKeyPress = { [weak self] press in self?.handle(press) ?? false }
        playerView.controls.onCommand = { [weak self] command in self?.perform(command) }
        playerView.controls.onHover = { [weak self] seconds, x in self?.hoverPreview(seconds: seconds, x: x) }
        playerView.onChromeVisibilityChange = { [weak self] visible in self?.setTitleBarVisible(visible) }
        controller.onStateChange = { [weak self] state in self?.render(state) }
        sidebar.onPlay = { [weak self] videoID in self?.coordinator.play(videoID) }
        // Covers the popup in the sidebar's own header and the View menu alike: both go through `setMode`.
        sidebar.onModeChange = { [weak self] _ in self?.saveSidebarSettings() }
        coordinator.onQueueChange = { [weak self] in self?.refreshSidebar() }
        installSidebarButton()
        refreshSidebar()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Playback

    func open(_ input: LaunchInput) {
        Task { await controller.open(input) }
    }

    func perform(_ command: PlayerCommand) {
        switch command {
        case .toggleFullScreen:
            (miniPlayer == nil ? window : nil)?.toggleFullScreen(nil)
        case .close:
            (miniPlayer?.window ?? window)?.performClose(nil)
        case .toggleMiniPlayer: toggleMiniPlayer(nil)
        case .fitWindowToVideo: fitWindowToVideo(nil)
        case .nextChapter:
            if let target = timeline.nextStart(from: controller.state.position) {
                controller.perform(.seekAbsolute(seconds: target))
            } else {
                NSSound.beep()
            }
        case .previousChapter:
            if let target = timeline.previousStart(from: controller.state.position) {
                controller.perform(.seekAbsolute(seconds: target))
            } else {
                NSSound.beep()
            }
        case .toggleChaptersPanel: toggleChaptersPanel(nil)
        case .toggleSubtitlesPanel: toggleSubtitlesPanel(nil)
        case let .adjustSubtitleDelay(delta):
            send(subtitles.setDelay(((subtitles.delay + delta) * 10).rounded() / 10))
            refreshSubtitlesPanel()
        default: controller.perform(command)
        }
    }

    /// Shows or hides the chapters panel. Available even when the video has no chapters at all — which is the only
    /// case this build can ever exercise — so the panel can say so rather than the menu item silently refusing.
    @objc func toggleChaptersPanel(_ sender: Any?) {
        if chaptersPanel.window?.isVisible == true {
            chaptersPanel.close()
        } else {
            chaptersPanel.setChapters(timeline.chapters)
            chaptersPanel.setCurrent(timeline.index(at: controller.state.position))
            chaptersPanel.showWindow(nil)
        }
    }

    /// Shows or hides the subtitles panel. Unlike the chapters panel, this one has nothing useful to say without a
    /// video that actually offers caption tracks, so opening it is refused rather than shown empty.
    @objc func toggleSubtitlesPanel(_ sender: Any?) {
        guard let stream = controller.state.stream, !stream.captionTracks.isEmpty else {
            NSSound.beep()
            return
        }
        if subtitlesPanel.window?.isVisible == true {
            subtitlesPanel.close()
        } else {
            refreshSubtitlesPanel()
            subtitlesPanel.showWindow(nil)
        }
    }

    /// Moves the video into a small floating window, or brings it back. The view — and with it mpv's render context —
    /// is moved, never rebuilt.
    @objc func toggleMiniPlayer(_ sender: Any?) {
        if miniPlayer != nil {
            leaveMiniPlayer()
        } else {
            enterMiniPlayer()
        }
    }

    private func enterMiniPlayer() {
        guard miniPlayer == nil, let screen = (window?.screen ?? NSScreen.main)?.visibleFrame else { return }
        if window?.styleMask.contains(.fullScreen) == true { window?.toggleFullScreen(nil) }
        let size = MiniPlayerGeometry.size(for: controller.state.videoSize, visibleFrame: screen)
        let mini = MiniPlayerWindowController(
            contentSize: size,
            aspectRatio: controller.state.videoSize?.aspectRatio ?? 16.0 / 9.0
        )
        mini.onClose = { [weak self] in self?.leaveMiniPlayer() }
        mini.adopt(playerView)
        // The remembered corner may come from a display that is no longer attached, so the frame is put back on the
        // screen in use before it is shown.
        mini.window?.setFrame(
            MiniPlayerGeometry.clamped(
                MiniPlayerGeometry.frame(size: size, corner: miniPlayerCorner, visibleFrame: screen),
                visibleFrame: screen
            ),
            display: true
        )
        miniPlayer = mini
        mini.showWindow(nil)
        mini.window?.makeFirstResponder(playerView)
        window?.orderOut(nil)
    }

    private func leaveMiniPlayer() {
        guard let mini = miniPlayer else { return }
        miniPlayer = nil
        if let frame = mini.window?.frame, let screen = (mini.window?.screen ?? NSScreen.main)?.visibleFrame {
            miniPlayerCorner = MiniPlayerGeometry.nearestCorner(of: frame, visibleFrame: screen)
        }
        MiniPlayerWindowController.pin(playerView, into: playerContainer)
        mini.onClose = nil
        mini.close()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(playerView)
    }

    private func refreshSubtitlesPanel() {
        subtitlesPanel.setTracks(
            controller.state.stream?.captionTracks ?? [],
            selected: subtitles.selected,
            style: subtitles.style,
            delay: subtitles.delay
        )
    }

    /// Downloads the track if it is new, writes it as a file and tells mpv to use it.
    private func chooseSubtitle(_ track: CaptionTrack?) {
        guard let track, let stream = controller.state.stream, let videoID = stream.videoID else {
            send(subtitles.disable())
            playerView.controls.setSubtitlesActive(false)
            return
        }
        subtitlesPanel.setStatus("Loading \(track.menuTitle)…")
        Task { [weak self] in
            guard let self else { return }
            do {
                let cues: [CaptionCue]
                if let cached = self.loadedCues[track.id] {
                    cues = cached
                } else {
                    cues = try await self.captions.cues(for: track, userAgent: stream.userAgent ?? ClientProfile.visionOS.userAgent)
                    self.loadedCues[track.id] = cues
                }
                let file = try SubtitleSession.write(
                    cues: cues, for: track, videoID: videoID, in: SubtitleSession.defaultDirectory()
                )
                self.send(self.subtitles.select(track, file: file))
                self.playerView.controls.setSubtitlesActive(true)
                self.subtitlesPanel.setStatus("\(cues.count) lines")
            } catch {
                self.subtitlesPanel.setStatus("Could not load \(track.menuTitle)")
                self.report(error, title: "Cue could not load those subtitles")
            }
        }
    }

    /// Writes the selected track as SRT or VTT wherever the user says.
    private func exportSubtitle(as format: ExportFormat) {
        guard let window, let track = subtitles.selected, let cues = loadedCues[track.id], !cues.isEmpty else {
            NSSound.beep()
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(controller.state.stream?.videoID?.rawValue ?? "subtitles").\(track.fileNameStem).\(format.fileExtension)"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let text = SubtitleWriter.text(cues, as: format)
                try Data(text.utf8).write(to: url, options: .atomic)
                // The export is the owner's viewing material: as private as the queue export (0600), not whatever
                // the umask leaves an atomic write with.
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                self.report(error, title: "Cue could not export those subtitles")
            }
        }
    }

    private func send(_ commands: [PlayerCommand]) {
        for command in commands { controller.perform(command) }
    }

    /// The pointer moved over the seek bar. The time and the chapter appear immediately; the frame follows when its
    /// sheet arrives, which is usually instant after the first hover.
    private func hoverPreview(seconds: Double?, x: CGFloat) {
        guard let seconds, let stream = controller.state.stream else {
            playerView.hidePreview()
            return
        }
        previewToken += 1
        let token = previewToken
        playerView.placePreview(atX: x)
        playerView.showPreview(seconds: seconds, chapter: timeline.chapter(at: seconds)?.title, image: nil)

        guard let frame = PreviewFrame.frame(at: seconds, duration: stream.duration, storyboard: stream.storyboard) else { return }
        let store = storyboardStore(for: stream)
        Task { [weak self] in
            guard let data = try? await store.sheet(at: frame.url) else { return }
            guard let self, token == self.previewToken else { return }
            self.playerView.showPreview(
                seconds: seconds,
                chapter: self.timeline.chapter(at: seconds)?.title,
                image: PreviewPopover.tile(frame, from: data)
            )
        }
    }

    private func storyboardStore(for stream: PlayableStream) -> StoryboardStore {
        if let storyboards { return storyboards }
        let store = StoryboardStore(userAgent: stream.userAgent ?? ClientProfile.visionOS.userAgent)
        storyboards = store
        return store
    }

    /// Edit ▸ Paste (⌘V): queues every video in the pasteboard, and plays the first one when nothing is playing.
    @objc func paste(_ sender: Any?) {
        let videoIDs = AddRequest.videoIDs(in: NSPasteboard.general.string(forType: .string) ?? "")
        guard !videoIDs.isEmpty else {
            NSSound.beep()
            return
        }
        add(videoIDs, playFirst: controller.state.stream == nil)
    }

    /// A `cue://add?url=…` link. A link that cannot be used says so instead of doing nothing.
    func handleAddLink(_ url: URL) {
        do {
            add([try AddRequest.videoID(from: url)], playFirst: controller.state.stream == nil)
        } catch {
            report(error, title: "Cue could not add that link")
        }
    }

    /// Adds videos at the end of the queue.
    func add(_ videoIDs: [VideoID], playFirst: Bool) {
        for videoID in videoIDs {
            if (try? store.add(videoID)) == nil {
                logger.error("Could not add a video to the queue")
            }
        }
        refreshSidebar()
        guard playFirst, let first = videoIDs.first else { return }
        // A video that was already queued is played too: that is what a repeated paste or link means.
        coordinator.play(first)
    }

    @objc func playNextInQueue(_ sender: Any?) {
        guard !coordinator.playNext() else { return }
        NSSound.beep()
    }

    @objc func markCurrentWatched(_ sender: Any?) {
        coordinator.markCurrentWatched()
    }

    /// Queue ▸ Play Next Automatically. Checked when finishing a video starts the next one.
    @objc func togglePlaysNextAutomatically(_ sender: Any?) {
        coordinator.playsNextAutomatically.toggle()
    }

    // MARK: - Sidebar

    @objc func toggleSidebar(_ sender: Any?) {
        let width = pushedSidebarWidth()
        let appearing = !sidebarHost.isVisible
        sidebarHost.toggleVisible()
        updateSidebarButton()
        resizeWindow(forSidebarWidth: width, appearing: appearing)
        saveSidebarSettings()
    }

    /// Writes the sidebar's appearance the moment it changes, assembled from the live objects rather than from
    /// anything this class keeps in step by hand.
    private func saveSidebarSettings() {
        preferences.sidebar = SidebarSettings(
            mode: sidebar.mode,
            layout: sidebarHost.layout,
            isVisible: sidebarHost.isVisible
        )
    }

    /// The width the pushed sidebar takes, read from the item while it is on screen and remembered for when it is not.
    private func pushedSidebarWidth() -> CGFloat {
        let current = sidebarItem.viewController.view.frame.width
        if sidebarHost.isVisible, current > 0 { lastSidebarWidth = current }
        return lastSidebarWidth
    }

    /// Takes the sidebar's width out of the window rather than out of the picture, so showing or hiding the queue
    /// leaves the video area the same shape and mpv never adds bars to a video it had already fitted.
    ///
    /// Nothing to do in full screen, where the window cannot resize, nor in overlay layout, where the sidebar floats
    /// over the video and the video area never changed size in the first place.
    private func resizeWindow(forSidebarWidth width: CGFloat, appearing: Bool) {
        guard sidebarHost.layout == .push, width > 0, let window,
              !window.styleMask.contains(.fullScreen),
              let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let frame = WindowGeometry.frameAdjustedForSidebar(
            window: window.frame,
            sidebarWidth: width,
            appearing: appearing,
            minimumSize: window.frameRect(forContentRect: NSRect(origin: .zero, size: window.contentMinSize)).size,
            visibleFrame: visible
        )
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true)
    }

    @objc func cycleSidebarMode(_ sender: Any?) {
        sidebar.setMode(sidebar.mode.next)
    }

    @objc func toggleSidebarLayout(_ sender: Any?) {
        sidebarHost.setLayout(sidebarHost.layout == .push ? .overlay : .push)
        updateSidebarButton()
        saveSidebarSettings()
    }

    /// Puts the toggle in the title bar, as a leading accessory. That is where Finder, Safari and Mail keep theirs,
    /// and it is the only way to sit beside the traffic lights without guessing at their position: AppKit lays the
    /// accessory out after them, at the system's spacing, at every title bar height and on both sides of a full
    /// screen transition. It goes through `toggleSidebar(_:)` like the menu item does, so there is one way to hide a
    /// sidebar.
    private func installSidebarButton() {
        sidebarButton.target = self
        sidebarButton.action = #selector(toggleSidebar(_:))
        sidebarButton.translatesAutoresizingMaskIntoConstraints = false
        let fitting = sidebarButton.fittingSize
        let container = NSView(frame: NSRect(x: 0, y: 0, width: fitting.width + 12, height: fitting.height + 4))
        container.addSubview(sidebarButton)
        NSLayoutConstraint.activate([
            sidebarButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            sidebarButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            sidebarButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        sidebarAccessory.view = container
        sidebarAccessory.layoutAttribute = .leading
        updateSidebarButton()
        window?.addTitlebarAccessoryViewController(sidebarAccessory)
    }

    /// The toggle says what it will do, not what it shows now, and the accessibility label says the same thing as the
    /// tooltip. Position is no longer any of this method's business: the title bar owns it.
    private func updateSidebarButton() {
        let label = sidebarHost.isVisible ? "Hide Sidebar" : "Show Sidebar"
        sidebarButton.toolTip = label
        sidebarButton.setAccessibilityLabel(label)
        // The title bar spans the whole window, so what lies under this button changes with the sidebar. Over the
        // sidebar it is a surface that follows the system appearance, and a nil tint lets the glyph follow it too.
        // Over the video it is the picture, which is always dark, so the glyph goes white like every other control
        // that sits on the picture. Without this it inherits a dark tint in a light appearance and disappears.
        sidebarButton.contentTintColor = sidebarHost.isVisible ? nil : .white
    }

    private static func sidebarToggleButton() -> NSButton {
        let image = NSImage(systemSymbolName: "sidebar.leading", accessibilityDescription: "Show Sidebar")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .medium))
        let button = NSButton(image: image ?? NSImage(), target: nil, action: nil)
        button.isBordered = false
        button.refusesFirstResponder = true
        return button
    }

    private func refreshSidebar() {
        sidebar.setCurrentVideo(coordinator.currentVideoID)
    }

    // MARK: - Import and export

    @objc func importQueue(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.message = "Choose a URL list, a Cue JSON file or a CSV export."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.runImport(from: url)
        }
    }

    @objc func exportQueue(_ sender: Any?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowsOtherFileTypes = true
        panel.nameFieldStringValue = QueueExport.suggestedFileName(for: .json, on: Date())
        panel.message = "The extension decides the format: .json, .csv or .txt for a URL list."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.runExport(to: url)
        }
    }

    private func runImport(from url: URL) {
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            let format = QueueFormat.detect(fileExtension: url.pathExtension, contents: contents)
            let parsed = try QueueImport.candidates(in: contents, format: format)
            let report = try QueueImport.apply(parsed.candidates, unreadable: parsed.unreadable, to: store)
            refreshSidebar()
            let alert = NSAlert()
            alert.messageText = "Imported \(format.title)"
            alert.informativeText = report.summary
            alert.runModal()
        } catch {
            report(error, title: "Cue could not import that file")
        }
    }

    private func runExport(to url: URL) {
        do {
            let format = QueueFormat.detectForExport(fileExtension: url.pathExtension)
            let videos = try store.videos()
            let text: String
            switch format {
            case .urlList: text = QueueExport.urlList(videos)
            case .json: text = try QueueExport.json(videos)
            case .csv: text = QueueExport.csv(videos)
            }
            try Data(text.utf8).write(to: url, options: .atomic)
            // The export is the owner's viewing history: keep it as private as the database it came from (0600),
            // rather than whatever the umask leaves an atomic write with.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            report(error, title: "Cue could not export the queue")
        }
    }

    /// Alerts go through the same redaction as the log: an error carrying a signed stream URL must not put the
    /// user's IP address on screen, where it ends up in screenshots.
    private func report(_ error: any Error, title: String) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = LogRedactor.redact(message)
        alert.runModal()
    }

    // MARK: - Window

    /// Saves the resume position, frees the render context, then destroys mpv. Safe to call more than once.
    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        leaveMiniPlayer()
        SubtitleSession.removeFiles(in: SubtitleSession.defaultDirectory())
        controller.close()
        playerView.videoView.videoLayer.teardown()
        do {
            try engine.shutdown()
        } catch {
            logger.error("mpv shutdown failed: \(String(describing: error), privacy: .public)")
        }
    }

    func windowWillClose(_ notification: Notification) {
        shutdown()
    }

    /// Fades the title bar with the controls.
    private func setTitleBarVisible(_ visible: Bool) {
        chromeIsVisible = visible
        applyTitleBarVisibility()
    }

    /// Brings the title bar to what the chrome is doing. The traffic lights stay put while the pointer is up there,
    /// and the bar never fades while the window is not key: a window you are about to click must show its buttons.
    ///
    /// The sidebar toggle fades in the same animation group as the traffic lights, because it is now one of them:
    /// they appear and disappear together, from one decision, and nothing else in the app writes the accessory's
    /// alpha. `isHidden` is settled from the alpha the fade actually ended on, so a fade in that overtakes a fade out
    /// leaves the toggle visible and clickable, and an accessory at alpha 0 is never left hit testing.
    private func applyTitleBarVisibility() {
        guard let window else { return }
        let accessory = sidebarAccessory.view
        // In full screen the title bar is AppKit's to slide in and out, accessory included. Anything faded here would
        // stay faded behind its back, so the toggle is put back to full alpha and left alone.
        guard !window.styleMask.contains(.fullScreen) else {
            accessory.isHidden = false
            accessory.alphaValue = 1
            return
        }
        // `contentLayoutRect` is the part of the content view the title bar does not cover, in the same coordinate
        // space the pointer is reported in. Comparing against its top asks the window where its title bar ends
        // instead of assuming a height, and it keeps working at any title bar size.
        let pointerIsInTitleArea = window.mouseLocationOutsideOfEventStream.y > window.contentLayoutRect.maxY
        let shown = chromeIsVisible || pointerIsInTitleArea || !window.isKeyWindow
        // Unhidden before the fade in, or there would be nothing on screen for it to act on.
        if shown { accessory.isHidden = false }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.animator().alphaValue = shown ? 1 : 0
            }
            accessory.animator().alphaValue = shown ? 1 : 0
        } completionHandler: {
            // AppKit runs this on the main thread, but the handler itself is `@Sendable`, so the isolation has to be
            // stated rather than assumed by the compiler.
            MainActor.assumeIsolated {
                accessory.isHidden = accessory.alphaValue == 0
            }
        }
        window.titleVisibility = shown ? .visible : .hidden
    }

    /// A panel taking key focus sends no exit event to the seek bar, so without this the preview would be left hanging
    /// over the video. The player view knows the one way to take it off screen.
    func windowDidResignKey(_ notification: Notification) {
        playerView.hidePreview()
    }

    /// Full screen takes the title bar away and gives it back, so both transitions re-apply what the chrome is doing:
    /// leaving is what would otherwise restore a title bar still faded out from before, with no pointer move due to
    /// bring it back.
    func windowDidEnterFullScreen(_ notification: Notification) {
        playerView.controls.windowIsFullScreen = true
        applyTitleBarVisibility()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        playerView.controls.windowIsFullScreen = false
        applyTitleBarVisibility()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window else { return }
        playerView.videoView.videoLayer.setVisible(window.occlusionState.contains(.visible))
    }

    private func handle(_ press: KeyPress) -> Bool {
        guard let command = KeyBindings.standard.command(for: press) else { return false }
        perform(command)
        return true
    }

    private func render(_ state: PlayerState) {
        window?.title = state.windowTitle
        window?.subtitle = state.windowSubtitle
        playerView.update(state)
        if state.stream != timeline.streamReference {
            timeline = ChapterTimeline(stream: state.stream)
            storyboards = nil
            playerView.hidePreview()
            loadedCues.removeAll()
            subtitles = SubtitleSession(keeping: subtitles)
            playerView.controls.setSubtitlesActive(false)
            if subtitlesPanel.window?.isVisible == true { refreshSubtitlesPanel() }
        }
        if chaptersPanel.window?.isVisible == true {
            chaptersPanel.setChapters(timeline.chapters)
            chaptersPanel.setCurrent(timeline.index(at: state.position))
        }
        if let size = state.videoSize { fit(to: size) }
        if let stream = state.stream, stream.videoURL != loggedDecodingFor {
            loggedDecodingFor = stream.videoURL
            if stream.decoding == .software {
                logger.notice("No hardware-decodable stream was offered; decoding in software")
            }
        }
        // The queue decides what "watched" means and what plays next; the window only forwards the state.
        coordinator.playerStateChanged(state)
    }

    /// Sizes the window to the video before the first frame (from the source's announced size) and again only if mpv
    /// reports a different aspect. Keeps the top-left corner. A pushed sidebar is added on top of the video's width,
    /// so the video itself keeps its size.
    private func fit(to size: VideoSize) {
        guard let window, WindowGeometry.needsRefit(fittedTo: fittedVideoSize, reported: size) else { return }
        fittedVideoSize = size
        guard !window.styleMask.contains(.fullScreen),
              let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let sidebarWidth = sidebarHost.layout == .push && sidebarHost.isVisible ? sidebarItem.viewController.view.frame.width : 0
        let video = WindowGeometry.contentSize(for: size, visibleScreenSize: CGSize(
            width: max(visible.size.width - sidebarWidth, 1),
            height: visible.size.height
        ))
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(CGSize(width: video.width + sidebarWidth, height: video.height))
        window.setFrameTopLeftPoint(topLeft)
        window.setFrame(window.constrainFrameRect(window.frame, to: window.screen), display: true)
    }

    /// View ▸ Fit Window to Video. Resizes the window until the video area has the video's exact shape, so mpv stops
    /// padding the picture with black. Dragging a corner cannot land on that shape, which is why this exists; the rule
    /// itself lives in `WindowGeometry`, and this only gathers what it needs and applies what it returns.
    @objc func fitWindowToVideo(_ sender: Any?) {
        guard canFitWindowToVideo, let window, let video = controller.state.videoSize,
              let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let frame = WindowGeometry.frameFittedToVideo(
            window: window.frame,
            contentSize: window.contentRect(forFrameRect: window.frame).size,
            aspectRatio: video.aspectRatio,
            // Only a pushed sidebar takes width away from the picture; an overlaid one floats over it.
            sidebarWidth: sidebarHost.layout == .push && sidebarHost.isVisible
                ? sidebarItem.viewController.view.frame.width
                : 0,
            minimumContentSize: window.contentMinSize,
            visibleFrame: visible
        )
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true)
    }

    /// There is nothing to fit until a video is loaded, full screen cannot resize the window at all, and while the
    /// mini player is up this window is hidden behind it — fitting a window the owner cannot see is worse than
    /// refusing. In all three cases the button and the menu item are greyed instead of refusing silently.
    var canFitWindowToVideo: Bool {
        let phase = controller.state.phase
        guard phase == .ready || phase == .ended, miniPlayer == nil, let window else { return false }
        return !window.styleMask.contains(.fullScreen)
    }
}

extension PlayerWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(paste(_:)):
            // Only ask whether the pasteboard *offers* text, never read it here: menu validation runs every time a
            // menu opens, with no gesture behind it, and reading pasteboard contents that way is what makes the
            // system warn the user that an app is looking at what they copied. `paste(_:)` reads it for real, once,
            // when they actually choose the item - and still beeps if it holds no video.
            return NSPasteboard.general.types?.contains(.string) ?? false
        case #selector(playNextInQueue(_:)):
            // Mirrors what `playNext()` would do, without consuming anything: nothing pending means nothing to do.
            return coordinator.canPlayNext
        case #selector(markCurrentWatched(_:)):
            // Nothing is playing when the coordinator has no current video, so there is nothing to mark.
            return coordinator.currentVideoID != nil
        case #selector(togglePlaysNextAutomatically(_:)):
            menuItem.state = coordinator.playsNextAutomatically ? .on : .off
            return true
        case #selector(toggleSidebar(_:)), #selector(cycleSidebarMode(_:)), #selector(toggleSidebarLayout(_:)),
             #selector(importQueue(_:)), #selector(exportQueue(_:)), #selector(toggleChaptersPanel(_:)):
            // Always available: they only open a panel or flip a display mode, regardless of queue or player state.
            // The chapters panel in particular must stay reachable with no chapters at all, so it can say so.
            return true
        case #selector(toggleSubtitlesPanel(_:)):
            return !(controller.state.stream?.captionTracks.isEmpty ?? true)
        case #selector(fitWindowToVideo(_:)):
            return canFitWindowToVideo
        default:
            // No superclass implements this protocol here (NSWindowController does not conform on its own), so an
            // unrecognized selector — one this object was never meant to validate — is allowed rather than guessed at.
            return true
        }
    }
}
