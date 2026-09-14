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
    /// The chapters and subtitles lists, in the trailing inspector rather than in floating windows of their own.
    private let inspector: InspectorViewController
    private let inspectorItem: NSSplitViewItem
    private var fittedVideoSize: VideoSize?
    /// The chapters of whatever is playing, rebuilt when the stream changes.
    private var timeline = ChapterTimeline(chapters: [], duration: nil)
    /// Storyboard sheets for the video playing now. Recreated per video so nothing survives into the next one.
    private var storyboards: StoryboardStore?
    /// Rises with every hover, so a sheet that arrives late for a position the pointer has left is dropped.
    private var previewToken = 0
    private var loggedDecodingFor: URL?
    /// Catches the bare keys before any view can consume them. See `installKeyMonitor()`.
    private var keyMonitor: Any?
    private var isShutDown = false
    private let logger = Logger(subsystem: "com.neverbot.cue", category: "player")

    private var subtitles = SubtitleSession()
    /// Which audio language is playing, and what the video offers instead. Replaced for every video: the languages
    /// belong to the video, not to the user.
    private var audio = AudioTrackSession()
    /// Cues already downloaded for the video playing now, by track id.
    private var loadedCues: [String: [CaptionCue]] = [:]
    private let captions = CaptionLoader()

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
        let inspectorSettings = preferences.inspector
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
        // Just above the video, not at the top of the scale. A split view hands new width to its lowest-priority item
        // first, so the queue only has to outrank the video for the picture to receive what the window gains. Setting
        // this to `.defaultHigh` also achieved that, and cost the divider: at 750 the item reads as fixed width and
        // stops being draggable. One point above the video's 250 keeps the resize behaviour and gives the handle back.
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.defaultLow.rawValue + 1)

        // The chapters and the subtitles live in a trailing inspector, which is the platform's own construction for a
        // second column beside the content: it takes no key focus from the player, cannot drift behind the window,
        // and sits in the same window as the queue's leading sidebar.
        let inspector = InspectorViewController(tab: inspectorSettings.tab)
        self.inspector = inspector
        inspectorItem = NSSplitViewItem(inspectorWithViewController: inspector)
        inspectorItem.minimumThickness = 240
        inspectorItem.maximumThickness = 420
        inspectorItem.canCollapse = true
        // A split view hands width to its items in order of holding priority, lowest first. Left at the default the
        // inspector was as willing to grow as the video beside it, so the width the window gained when the inspector
        // opened was split between the two and the picture came back with bars around it. Held high, the inspector
        // keeps the width it has and the video is the only item left to take the difference.
        inspectorItem.holdingPriority = NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.defaultLow.rawValue + 1)
        // Always closed at launch, however the last session left it: the picture owns the window until the chapters
        // or the subtitles are actually asked for. Only the page above is restored, so reopening lands where it was.
        inspectorItem.isCollapsed = true

        splitViewController = NSSplitViewController()
        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(NSSplitViewItem(viewController: playerViewController))
        splitViewController.addSplitViewItem(inspectorItem)

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
        installKeyMonitor()
        playerView.onKeyPress = { [weak self] press in self?.handle(press) ?? false }
        playerView.controls.onCommand = { [weak self] command in self?.perform(command) }
        playerView.controls.onHover = { [weak self] seconds, x in self?.hoverPreview(seconds: seconds, x: x) }
        playerView.onChromeVisibilityChange = { [weak self] visible in self?.chromeVisibilityChanged(visible) }
        controller.onStateChange = { [weak self] state in self?.render(state) }
        sidebar.onPlay = { [weak self] videoID in self?.coordinator.play(videoID) }
        // Covers the popup in the sidebar's own header and the View menu alike: both go through `setMode`.
        sidebar.onModeChange = { [weak self] _ in self?.saveSidebarSettings() }
        // Both halves of the window take a dropped file, because the sidebar may well be hidden when one arrives, and
        // both go to the same place: one question, then the same import the menu item runs.
        sidebar.onFileDrop = { [weak self] url in self?.offerImport(from: url) }
        playerView.onFileDrop = { [weak self] url in self?.offerImport(from: url) }
        coordinator.onQueueChange = { [weak self] in self?.refreshSidebar() }
        // Every callback the two floating panels had, kept exactly as it was; only where their views hang changed.
        inspector.chapters.onSelect = { [weak self] seconds in self?.controller.perform(.seekAbsolute(seconds: seconds)) }
        inspector.subtitles.onSelect = { [weak self] track in self?.chooseSubtitle(track) }
        inspector.subtitles.onStyleChange = { [weak self] style in
            guard let self else { return }
            self.send(self.subtitles.apply(style))
            // The style carries the resting position with it, so applying one while the bar is on screen would drop
            // the subtitles straight back underneath it. The lift goes back on top of the new baseline.
            self.applySubtitlePosition()
        }
        inspector.subtitles.onDelayChange = { [weak self] delay in self?.send(self?.subtitles.setDelay(delay) ?? []) }
        inspector.subtitles.onExport = { [weak self] format in self?.exportSubtitle(as: format) }
        inspector.audio.onSelect = { [weak self] id in self?.chooseAudioTrack(id) }
        inspector.onTabChange = { [weak self] _ in
            self?.refreshInspector()
            self?.saveInspectorSettings()
        }
        // The coordinator holds this while the app runs; the store is where it survives a quit.
        coordinator.playsNextAutomatically = preferences.playsNextAutomatically
        // The settings window writes the same keys this class does. Rather than the two knowing about each other,
        // both write to the store and read back from it: whatever changed a setting, this window catches up here.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesChanged),
            name: Preferences.didChangeNotification,
            object: nil
        )
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
        case .toggleChaptersInspector: toggleChaptersInspector(nil)
        case .toggleSubtitlesInspector: toggleSubtitlesInspector(nil)
        case .toggleAudioInspector: toggleAudioInspector(nil)
        case let .adjustSubtitleDelay(delta):
            send(subtitles.setDelay(((subtitles.delay + delta) * 10).rounded() / 10))
            refreshSubtitlesInspector()
        default: controller.perform(command)
        }
    }

    /// Opens the inspector on its chapters page, or closes it when that page is already in front. Available even when
    /// the video has no chapters at all — which is the only case this build can ever exercise — so the page can say
    /// so rather than the menu item silently refusing.
    @objc func toggleChaptersInspector(_ sender: Any?) {
        toggleInspector(showing: .chapters)
    }

    /// Opens the inspector on its subtitles page, or closes it when that page is already in front. Available with no
    /// caption tracks at all, exactly like chapters: the page says the video offers none. Refusing here while the
    /// page's own segment opened it anyway left one page answering two different ways depending on how it was asked.
    @objc func toggleSubtitlesInspector(_ sender: Any?) {
        toggleInspector(showing: .subtitles)
    }

    /// Opens the inspector on its audio page, or closes it when that page is already in front. Available on a video
    /// with one soundtrack, like the other two: the page says so plainly, which beats a shortcut that beeps.
    @objc func toggleAudioInspector(_ sender: Any?) {
        toggleInspector(showing: .audio)
    }

    /// The one way the inspector opens, closes and changes page, whichever control asked. Asking again for the page
    /// already in front closes it, which is how the two panels behaved when their shortcut was pressed twice.
    private func toggleInspector(showing tab: InspectorTab) {
        if isInspectorVisible, inspector.tab == tab {
            setInspectorVisible(false)
        } else {
            inspector.setTab(tab)
            refreshInspector()
            setInspectorVisible(true)
        }
        saveInspectorSettings()
    }

    private var isInspectorVisible: Bool { !inspectorItem.isCollapsed }

    /// Shows or hides the inspector and takes its width out of the window rather than out of the picture, so the
    /// video area is left the shape it already had.
    ///
    /// That width is measured, never predicted. A split view settles a collapse against both items' holding
    /// priorities, their minimum and maximum thicknesses and wherever the divider was last dragged to, so the width
    /// the inspector takes is not always the width it was asked for — and adjusting the window by a number the item
    /// then ignores is what left the picture pillarboxed. The picture is read before and after instead, and the
    /// window is given back exactly what it lost.
    private func setInspectorVisible(_ visible: Bool) {
        guard visible != isInspectorVisible else { return }
        let videoWidth = playerContainer.frame.width
        inspectorItem.isCollapsed = !visible
        // Collapsing only changes constraints, so nothing has moved yet: without this the measurement below would
        // read the geometry the window had before the inspector was asked for at all.
        splitViewController.view.layoutSubtreeIfNeeded()
        restoreVideoWidth(to: videoWidth)
    }

    /// Gives the window back the width the picture just lost, or takes back the width it just gained, then reads the
    /// picture again rather than trusting the first pass: a window can run into the edge of the screen or into its
    /// own minimum size, and a split view under a resize need not hand every new point to the video. A second pass
    /// settles what the first could not, and a window that cannot move any further is left alone rather than nudged
    /// forever.
    private func restoreVideoWidth(to width: CGFloat) {
        for _ in 0..<2 {
            guard let correction = WindowGeometry.videoWidthCorrection(
                before: width,
                now: playerContainer.frame.width
            ) else { return }
            let before = window?.frame
            resizeWindow(byWidth: correction.width, appearing: correction.appearing)
            guard window?.frame != before else { return }
            splitViewController.view.layoutSubtreeIfNeeded()
        }
    }

    /// Writes the inspector's page the moment it changes, assembled from the live objects like the sidebar's is.
    /// Whether it is open is not written: it starts closed at every launch regardless.
    private func saveInspectorSettings() {
        preferences.inspector = InspectorSettings(tab: inspector.tab)
    }

    /// Brings both pages to the video playing now. Only ever called while the inspector is on screen, so a hidden
    /// list is not rebuilt on every state change.
    private func refreshInspector() {
        inspector.chapters.setChapters(timeline.chapters)
        inspector.chapters.setCurrent(timeline.index(at: controller.state.position))
        refreshSubtitlesInspector()
        refreshAudioInspector()
    }

    /// What actually changes as a video plays: which chapter the playhead is in. Nothing else here follows the
    /// position, and rebuilding the rest on every tick is what broke choosing a subtitle — the player reports state
    /// several times a second, and each report used to repopulate the subtitles page and reset its selected row from
    /// `subtitles.selected`, which stays nil until an asynchronous download finishes. The chosen track was pushed
    /// back to "Off" milliseconds after the click, so the click looked as though it had done nothing at all.
    private func updateInspectorPosition() {
        inspector.chapters.setCurrent(timeline.index(at: controller.state.position))
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

    private func refreshSubtitlesInspector() {
        inspector.subtitles.setTracks(
            controller.state.stream?.captionTracks ?? [],
            selected: subtitles.selected,
            style: subtitles.style,
            delay: subtitles.delay
        )
    }

    private func refreshAudioInspector() {
        inspector.audio.setRows(AudioTrackPresentation.rows(for: audio.tracks, selected: audio.selectedID))
    }

    /// Switches the video's soundtrack to another language.
    ///
    /// Nothing is fetched and nothing is re-resolved: every language came from the same `/player` response, so its
    /// URL is already in hand. The external audio track is swapped on the file that is playing, which leaves the
    /// position and the pause state exactly where they were.
    private func chooseAudioTrack(_ id: String) {
        guard let option = audio.option(id: id) else { return }
        send(audio.select(option))
        refreshAudioInspector()
    }

    /// Downloads the track if it is new, writes it as a file and tells mpv to use it.
    private func chooseSubtitle(_ track: CaptionTrack?) {
        guard let track, let stream = controller.state.stream, let videoID = stream.videoID else {
            send(subtitles.disable())
            playerView.controls.setSubtitlesActive(false)
            return
        }
        inspector.subtitles.setStatus("Loading \(track.menuTitle)…")
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
                // Loading a track re-sends the whole style, resting position included, so the lift goes back on.
                self.applySubtitlePosition()
                self.playerView.controls.setSubtitlesActive(true)
                self.inspector.subtitles.setStatus("\(cues.count) lines")
            } catch {
                self.inspector.subtitles.setStatus("Could not load \(track.menuTitle)")
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
        // Written rather than only flipped, so it is still off after a quit. The settings window shows the same
        // setting and hears about this write, so the checkbox and the checkmark never disagree.
        preferences.playsNextAutomatically = !coordinator.playsNextAutomatically
    }

    // MARK: - Sidebar

    @objc func toggleSidebar(_ sender: Any?) {
        setSidebarVisible(!sidebarHost.isVisible)
        saveSidebarSettings()
    }

    /// Shows or hides the queue and takes its width out of the window rather than out of the picture, measured the
    /// same way the inspector measures: read the picture, collapse, let the layout settle, then give the window back
    /// what the picture lost. The width the column actually takes depends on holding priorities, thicknesses and
    /// wherever the divider was last dragged, so it is never assumed.
    ///
    /// Only in push layout. A floating sidebar is drawn over the video and the picture never changed size, so there
    /// is nothing to give back.
    private func setSidebarVisible(_ visible: Bool) {
        guard visible != sidebarHost.isVisible else { return }
        guard sidebarHost.layout == .push else {
            sidebarHost.setVisible(visible)
            updateSidebarButton()
            return
        }
        let videoWidth = playerContainer.frame.width
        sidebarHost.setVisible(visible)
        updateSidebarButton()
        splitViewController.view.layoutSubtreeIfNeeded()
        restoreVideoWidth(to: videoWidth)
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

    /// Something wrote a preference: this window, the settings window, or a reset. Everything here is brought to what
    /// is stored.
    ///
    /// This is also what runs after this class's own writes, which is why every step below is guarded by a comparison
    /// rather than applied blindly: applying a change that is already in place would call back into `saveSidebar`,
    /// write again, and post again. With the guards the second pass finds nothing to do and stops.
    @objc private func preferencesChanged() {
        coordinator.playsNextAutomatically = preferences.playsNextAutomatically
        let settings = preferences.sidebar
        if sidebar.mode != settings.mode { sidebar.setMode(settings.mode) }
        if sidebarHost.layout != settings.layout {
            sidebarHost.setLayout(settings.layout)
            updateSidebarButton()
        }
        if sidebarHost.isVisible != settings.isVisible {
            setSidebarVisible(settings.isVisible)
        }
        let inspectorSettings = preferences.inspector
        // The page only. Whether the inspector is open belongs to this window for as long as it runs and is never
        // restored from the store, so a reset cannot open it and the settings window cannot close it.
        if inspector.tab != inspectorSettings.tab { inspector.setTab(inspectorSettings.tab) }
    }

    /// Takes a column's width out of the window rather than out of the picture, so showing or hiding the queue or the
    /// inspector leaves the video area the same shape and mpv never adds bars to a video it had already fitted.
    ///
    /// Nothing to do in full screen, where the window cannot resize.
    private func resizeWindow(byWidth width: CGFloat, appearing: Bool) {
        guard width > 0, let window,
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

    /// Re-reads the queue into the sidebar, for a change made somewhere other than this window — the settings
    /// window's Queue section. The sidebar is the only copy of the queue on screen, so it catches up now rather than
    /// at the next launch.
    func refreshQueue() {
        refreshSidebar()
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

    /// The file the Import menu item chose, or the one the settings window's Queue section chose. Read, then applied:
    /// the panel was the question, so nothing else is asked.
    func runImport(from url: URL) {
        Task { [weak self] in
            guard let self else { return }
            do {
                self.applyImport(try await ImportFileReader.read(url), asSheet: false)
            } catch {
                self.report(error, title: "Cue could not import that file")
            }
        }
    }

    /// A file dropped on the sidebar or on the picture. The same reading and the same report as the menu item, with
    /// one thing in between: a drop is easy to do by accident, so the queue is not touched until the count on screen
    /// has been agreed to.
    func offerImport(from url: URL) {
        guard let window else { return }
        Task { [weak self] in
            guard let self else { return }
            let file: ParsedImportFile
            do {
                file = try await ImportFileReader.read(url)
            } catch {
                self.report(error, title: "Cue could not read that file", asSheet: true)
                return
            }
            let prompt = QueueImportPresentation.prompt(
                candidates: file.candidates.count,
                unreadable: file.unreadable.count
            )
            let alert = NSAlert()
            alert.messageText = prompt.message
            if let detail = prompt.detail { alert.informativeText = detail }
            // A file with nothing to add gets an acknowledgement, not a question with no answer.
            alert.addButton(withTitle: prompt.canAdd ? "Add" : "OK")
            if prompt.canAdd { alert.addButton(withTitle: "Cancel") }
            let response = await alert.beginSheetModal(for: window)
            guard prompt.canAdd, response == .alertFirstButtonReturn else { return }
            self.applyImport(file, asSheet: true)
        }
    }

    /// The one place an import reaches the queue, whichever way the file arrived.
    private func applyImport(_ file: ParsedImportFile, asSheet: Bool) {
        do {
            let report = try QueueImport.apply(file.candidates, unreadable: file.unreadable, to: store)
            refreshSidebar()
            let alert = NSAlert()
            alert.messageText = "Imported \(file.format.title)"
            alert.informativeText = report.summary
            present(alert, asSheet: asSheet)
        } catch {
            report(error, title: "Cue could not import that file", asSheet: asSheet)
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
    private func report(_ error: any Error, title: String, asSheet: Bool = false) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = LogRedactor.redact(message)
        present(alert, asSheet: asSheet)
    }

    /// A dropped file is answered on the window it was dropped on; a menu item that opened a panel keeps the modal it
    /// already had.
    private func present(_ alert: NSAlert, asSheet: Bool) {
        if asSheet, let window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    // MARK: - Window

    /// Saves the resume position, frees the render context, then destroys mpv. Safe to call more than once.
    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        // Before anything else: a monitor outliving its window would keep swallowing keys for the whole application.
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
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

    /// The controls appeared or disappeared. Two things follow them: the title bar fades with the chrome, and the
    /// subtitles move up out from under the bar for as long as it is on screen.
    private func chromeVisibilityChanged(_ visible: Bool) {
        setTitleBarVisible(visible)
        applySubtitlePosition()
    }

    /// Keeps the subtitles clear of the controls bar.
    ///
    /// `sub-pos` is a percentage of the picture's height, so the lift is worked out from what the bar actually covers
    /// — its laid-out height plus the inset it floats above the bottom edge — measured against the picture it covers.
    /// Nothing here is a number chosen by eye, and a change to the bar's contents carries through on its own.
    ///
    /// The user's own position stays the baseline: `SubtitleLift` takes the lift off it rather than replacing it, so
    /// whatever they chose is still where the subtitles rest once the bar fades. Harmless with no subtitle showing —
    /// mpv keeps `sub-pos` whether or not anything is being drawn with it.
    private func applySubtitlePosition() {
        controller.perform(SubtitleLift.command(
            baseline: subtitles.style.position,
            occludedHeight: chromeIsVisible ? playerView.controlsOccludedHeight : 0,
            pictureHeight: playerView.bounds.height
        ))
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

    /// Another window taking key focus sends no exit event to the seek bar, so without this the preview would be left
    /// hanging over the video. The player view knows the one way to take it off screen.
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

    /// The bare keys work wherever the focus happens to be.
    ///
    /// `PlayerView` only sees a key while it holds first responder, and this window now contains the queue's table,
    /// the inspector's two tables and its page control — each of which takes first responder the moment it is
    /// clicked. The queue's table does forward what it does not use, but that chain runs up through the split view
    /// to the window, and the player view is a sibling branch it never passes through: after clicking the queue,
    /// space stopped playing and pausing. A window controller sits at the end of every responder chain in its
    /// window, so whatever no view consumed arrives here and can still reach the player.
    ///
    /// Never while text is being edited: a field editor keeps its own keys, or typing a space into a text field
    /// would pause the video.
    /// Bare keys, caught before any view sees them.
    ///
    /// Handling them on the responder chain does not work here, and the first attempt at this proved it: `NSTableView`
    /// takes the space bar for its own type-select and does not pass it on, so with the queue or either inspector list
    /// focused the key was consumed before it could reach anything. That is why the previous fix — a `keyDown` on this
    /// controller, at the end of every chain — could never fire for the one key that was reported broken.
    ///
    /// A local monitor sees the event first, so no view can swallow it. Two guards keep it honest: only this window's
    /// events, and never while text is being edited, or a space typed into the add-a-video field would pause playback.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window,
                  !(self.window?.firstResponder is NSText),
                  let press = KeyPress(event: event), self.handle(press)
            else { return event }
            return nil
        }
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
            // The languages are the video's own, so nothing carries over: the new stream says what it offers and
            // which one it was loaded with.
            audio = AudioTrackSession(stream: state.stream)
            playerView.controls.setSubtitlesActive(false)
            // Which inspector buttons the bar shows is a property of the video, so it is settled here, where the new
            // stream arrives — not in `refreshInspector()`, which only runs while the inspector is open and would
            // leave the bar advertising the last video's pages until it was.
            playerView.controls.setInspectorAvailability(
                chapters: !timeline.isEmpty,
                subtitles: !(state.stream?.captionTracks ?? []).isEmpty,
                // The same rule the audio page lists by, so the button and the page can never disagree: one
                // soundtrack is no choice, and both treat it as nothing to show.
                audio: !AudioTrackPresentation.rows(for: audio.tracks, selected: audio.selectedID).isEmpty
            )
            // The whole inspector, not just the subtitles: a new video brings new chapters too, and the position
            // update below deliberately no longer rebuilds either list.
            if isInspectorVisible { refreshInspector() }
        }
        if isInspectorVisible { updateInspectorPosition() }
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
        let sidebarWidth = widthBesideVideo
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
            sidebarWidth: widthBesideVideo,
            minimumContentSize: window.contentMinSize,
            visibleFrame: visible
        )
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true)
    }

    /// Every point of window width that is not picture: the queue sidebar when it is pushed rather than overlaid, and
    /// the inspector when it is open. An overlaid sidebar floats over the video and takes nothing away from it.
    private var widthBesideVideo: CGFloat {
        let queue = sidebarHost.layout == .push && sidebarHost.isVisible
            ? sidebarItem.viewController.view.frame.width
            : 0
        return queue + (isInspectorVisible ? inspectorItem.viewController.view.frame.width : 0)
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
             #selector(importQueue(_:)), #selector(exportQueue(_:)), #selector(toggleChaptersInspector(_:)),
             #selector(toggleSubtitlesInspector(_:)), #selector(toggleAudioInspector(_:)):
            // Always available: they only open the inspector or flip a display mode, regardless of queue or player
            // state. Both inspector pages must stay reachable when they have nothing to show, so they can say so
            // rather than a shortcut beeping while the page's own segment opens it anyway.
            return true
        case #selector(fitWindowToVideo(_:)):
            return canFitWindowToVideo
        default:
            // No superclass implements this protocol here (NSWindowController does not conform on its own), so an
            // unrecognized selector — one this object was never meant to validate — is allowed rather than guessed at.
            return true
        }
    }
}
