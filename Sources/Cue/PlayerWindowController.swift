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
    private let playerView: PlayerView
    private let sidebar: QueueSidebarViewController
    private let sidebarHost: SidebarHost
    private let splitViewController: NSSplitViewController
    private let sidebarItem: NSSplitViewItem
    private var fittedVideoSize: VideoSize?
    /// The chapters of whatever is playing, rebuilt when the stream changes.
    private var timeline = ChapterTimeline(chapters: [], duration: nil)
    /// Storyboard sheets for the video playing now. Recreated per video so nothing survives into the next one.
    private var storyboards: StoryboardStore?
    /// Rises with every hover, so a sheet that arrives late for a position the pointer has left is dropped.
    private var previewToken = 0
    private var loggedDecodingFor: URL?
    private var isShutDown = false
    private let logger = Logger(subsystem: "com.neverbot.cue", category: "player")

    private lazy var chaptersPanel: ChaptersPanelController = {
        let panel = ChaptersPanelController()
        panel.onSelect = { [weak self] seconds in self?.controller.perform(.seekAbsolute(seconds: seconds)) }
        return panel
    }()

    init(
        engine: MPVPlaybackEngine,
        store: QueueStore,
        thumbnails: ThumbnailStore,
        resolver: any StreamResolving,
        resumeStore: any ResumeStore
    ) {
        self.engine = engine
        self.store = store
        controller = PlayerController(engine: engine, resolver: resolver, resumeStore: resumeStore)
        // Only a resolver that also does prefetching (PrefetchingResolver, in production) drives it; a bare
        // resolver leaves the queue's behaviour exactly as it was before prefetching existed.
        coordinator = QueueCoordinator(store: store, player: controller, prefetcher: resolver as? any StreamPrefetching)
        playerView = PlayerView(handle: engine.handle)
        sidebar = QueueSidebarViewController(store: store, thumbnails: thumbnails)

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
            parent: playerViewController
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
        coordinator.onQueueChange = { [weak self] in self?.refreshSidebar() }
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
        case .toggleFullScreen: window?.toggleFullScreen(nil)
        case .close: window?.performClose(nil)
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

    /// The pointer moved over the seek bar. The time and the chapter appear immediately; the frame follows when its
    /// sheet arrives, which is usually instant after the first hover.
    private func hoverPreview(seconds: Double?, x: CGFloat) {
        guard let seconds, let stream = controller.state.stream else {
            playerView.preview.hide()
            return
        }
        previewToken += 1
        let token = previewToken
        playerView.placePreview(atX: x)
        playerView.preview.show(seconds: seconds, chapter: timeline.chapter(at: seconds)?.title, image: nil)

        guard let frame = PreviewFrame.frame(at: seconds, duration: stream.duration, storyboard: stream.storyboard) else { return }
        let store = storyboardStore(for: stream)
        Task { [weak self] in
            guard let data = try? await store.sheet(at: frame.url) else { return }
            guard let self, token == self.previewToken else { return }
            self.playerView.preview.show(
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
        sidebarHost.toggleVisible()
    }

    @objc func cycleSidebarMode(_ sender: Any?) {
        sidebar.setMode(sidebar.mode.next)
    }

    @objc func toggleSidebarLayout(_ sender: Any?) {
        sidebarHost.setLayout(sidebarHost.layout == .push ? .overlay : .push)
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

    /// Fades the title bar with the controls. The traffic lights stay put while the pointer is up there, and the bar
    /// never fades while the window is not key: a window you are about to click must show its buttons.
    private func setTitleBarVisible(_ visible: Bool) {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        let pointerIsInTitleArea = window.mouseLocationOutsideOfEventStream.y > window.frame.height - 28
        let shown = visible || pointerIsInTitleArea || !window.isKeyWindow
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.animator().alphaValue = shown ? 1 : 0
            }
        }
        window.titleVisibility = shown ? .visible : .hidden
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
            playerView.preview.hide()
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
        default:
            // No superclass implements this protocol here (NSWindowController does not conform on its own), so an
            // unrecognized selector — one this object was never meant to validate — is allowed rather than guessed at.
            return true
        }
    }
}
