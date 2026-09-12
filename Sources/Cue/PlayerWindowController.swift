import AppKit
import CueCore
import CueMPV
import CuePlayer
import os

/// One player window: owns the engine, the controller and the video layer, and enforces the shutdown order
/// (controller → render context → mpv core).
final class PlayerWindowController: NSWindowController, NSWindowDelegate {
    let engine: MPVPlaybackEngine
    let controller: PlayerController
    private let playerView: PlayerView
    private var fittedVideoSize: VideoSize?
    private var loggedDecodingFor: URL?
    private var isShutDown = false
    private let logger = Logger(subsystem: "com.neverbot.cue", category: "player")

    init(engine: MPVPlaybackEngine) {
        self.engine = engine
        controller = PlayerController(engine: engine, resolver: Extractor(), resumeStore: JSONResumeStore.default())
        playerView = PlayerView(handle: engine.handle)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: WindowGeometry.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Cue"
        window.isRestorable = false
        window.backgroundColor = .black
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentMinSize = NSSize(width: 320, height: 180)
        window.contentView = playerView
        window.center()
        super.init(window: window)

        window.delegate = self
        window.makeFirstResponder(playerView)
        playerView.onKeyPress = { [weak self] press in self?.handle(press) ?? false }
        playerView.controls.onCommand = { [weak self] command in self?.perform(command) }
        controller.onStateChange = { [weak self] state in self?.render(state) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func open(_ input: LaunchInput) {
        Task { await controller.open(input) }
    }

    func perform(_ command: PlayerCommand) {
        switch command {
        case .toggleFullScreen: window?.toggleFullScreen(nil)
        case .close: window?.performClose(nil)
        default: controller.perform(command)
        }
    }

    /// Edit ▸ Paste (⌘V) arrives here through the responder chain.
    @objc func paste(_ sender: Any?) {
        guard let input = LaunchInput.parse(pastedText: NSPasteboard.general.string(forType: .string)) else {
            NSSound.beep()
            return
        }
        open(input)
    }

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
        if let size = state.videoSize { fit(to: size) }
        if let stream = state.stream, stream.videoURL != loggedDecodingFor {
            loggedDecodingFor = stream.videoURL
            if stream.decoding == .software {
                logger.notice("No hardware-decodable stream was offered; decoding in software")
            }
        }
    }

    /// Sizes the window to the video before the first frame (from the source's announced size) and again only if mpv
    /// reports a different aspect. Keeps the top-left corner and locks the aspect ratio for live resizing.
    private func fit(to size: VideoSize) {
        guard let window, WindowGeometry.needsRefit(fittedTo: fittedVideoSize, reported: size) else { return }
        fittedVideoSize = size
        window.contentAspectRatio = NSSize(width: size.width, height: size.height)
        guard !window.styleMask.contains(.fullScreen),
              let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(WindowGeometry.contentSize(for: size, visibleScreenSize: visible.size))
        window.setFrameTopLeftPoint(topLeft)
        window.setFrame(window.constrainFrameRect(window.frame, to: window.screen), display: true)
    }
}
