import AppKit
import CueMPV
import CuePlayer

/// The window's content: video, a status message and the controls overlay. Turns key events into `KeyPress`es.
final class PlayerView: NSView {
    let videoView: VideoView
    let controls = ControlsView()
    /// Owned rather than handed out: its visibility has exactly one route in, through `showPreview` and `hidePreview`.
    private let preview = PreviewPopover()
    var onKeyPress: ((KeyPress) -> Bool)?
    /// Called whenever the controls appear or disappear, so the window can fade its title bar with them.
    var onChromeVisibilityChange: ((Bool) -> Void)?
    /// Everything that comes and goes as one unit: the controls bar, the seek preview, and chrome that belongs to the
    /// window rather than to this view — the sidebar toggle, which sits in the container around the video.
    ///
    /// This list is the single source of truth for chrome visibility, and `fade(_:to:)` is the only code in the app
    /// that writes `alphaValue` or `isHidden` on any view in it. Holding the toggle strongly is not a cycle: the
    /// container owns it, and it points back here only through its action, which AppKit does not retain.
    private var chromeViews: [NSView] = []

    private let messageLabel = NSTextField(labelWithString: "")
    private let pausedIndicator = PausedIndicator()
    private var playerState = PlayerState()
    private var timeline = ChapterTimeline(chapters: [], duration: nil)
    private var hideTask: Task<Void, Never>?
    private var previewLeadingConstraint: NSLayoutConstraint!
    /// Whether the pointer is asking for a preview at all. What is actually on screen is this *and* the chrome being
    /// visible: the bubble belongs to the bar it hangs over and cannot outlast it.
    private var previewIsRequested = false
    /// Where the pointer was pressed, in window coordinates, so a release can tell a click from a window drag.
    private var pressLocation: NSPoint?

    init(handle: MPVHandle) {
        videoView = VideoView(handle: handle)
        super.init(frame: NSRect(origin: .zero, size: WindowGeometry.defaultContentSize))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        messageLabel.textColor = .secondaryLabelColor
        messageLabel.font = .systemFont(ofSize: 15)
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 3
        messageLabel.lineBreakMode = .byWordWrapping

        for view in [videoView, messageLabel, pausedIndicator, controls, preview] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            pausedIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            pausedIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            videoView.leadingAnchor.constraint(equalTo: leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: trailingAnchor),
            videoView.topAnchor.constraint(equalTo: topAnchor),
            videoView.bottomAnchor.constraint(equalTo: bottomAnchor),
            messageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            messageLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40),
            controls.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            controls.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            preview.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -8),
        ])
        previewLeadingConstraint = preview.leadingAnchor.constraint(equalTo: controls.leadingAnchor)
        previewLeadingConstraint.isActive = true
        registerChrome(controls)
        registerChrome(preview)
        update(playerState)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if let press = KeyPress(event: event), onKeyPress?(press) == true { return }
        super.keyDown(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        revealControls()
    }

    /// The pointer left the picture entirely, which the seek bar's own exit event does not always cover.
    override func mouseExited(with event: NSEvent) {
        hidePreview()
    }

    /// How far the pointer may travel between press and release and still count as a click rather than a drag.
    private static let dragSlop: CGFloat = 3

    override func mouseDown(with event: NSEvent) {
        pressLocation = event.locationInWindow
        // Passed on, so the window can still be moved by dragging the picture. A drag that the window takes over ends
        // without a mouse up here, which is one of the two reasons a drag never toggles playback.
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let start = pressLocation
        pressLocation = nil
        if event.clickCount == 2 {
            // The macOS convention, and the one the rest of the window already follows.
            controls.onCommand?(.toggleFullScreen)
        } else if event.clickCount == 1, let start, Self.isClick(from: start, to: event.locationInWindow) {
            // The same route as the play button: the window decides what a toggle means, this view only asks.
            controls.onCommand?(.togglePause)
        }
        super.mouseUp(with: event)
    }

    /// The second reason: a press that travelled was aimed at moving the window, not at the video under it.
    private static func isClick(from start: NSPoint, to end: NSPoint) -> Bool {
        abs(end.x - start.x) < dragSlop && abs(end.y - start.y) < dragSlop
    }

    func update(_ state: PlayerState) {
        playerState = state
        if state.stream != timeline.streamReference { timeline = ChapterTimeline(stream: state.stream) }
        controls.update(state, timeline: timeline)
        let message = Self.message(for: state.phase)
        messageLabel.stringValue = message ?? ""
        messageLabel.isHidden = message == nil
        // Only with a video loaded: in every other phase the message above owns the centre of the picture.
        pausedIndicator.setVisible(state.phase == .ready && state.isPaused)
        if state.phase != .ready || state.isPaused {
            revealControls()
        }
    }

    /// Places the preview over the seek bar, clamped so it never hangs off either end.
    func placePreview(atX x: CGFloat) {
        previewLeadingConstraint.constant = PreviewFrame.popoverX(
            centredOn: x,
            popoverWidth: preview.fittingSize.width,
            barWidth: controls.bounds.width
        )
    }

    /// The pointer is over the seek bar: fill the bubble in and let it appear, if the chrome is on screen at all.
    func showPreview(seconds: Double, chapter: String?, image: NSImage?) {
        // A hover that is only starting now must not flash the frame the last one left behind.
        if !previewIsRequested { preview.clear() }
        preview.update(seconds: seconds, chapter: chapter, image: image)
        previewIsRequested = true
        applyChrome()
    }

    /// The one way the preview leaves the screen. Everything that should take it away — the chrome fading out, the
    /// window losing key focus to a panel, the pointer leaving the seek bar or the player view altogether — comes
    /// through here, so no route can leave the bubble floating over a bare picture.
    func hidePreview() {
        guard previewIsRequested else { return }
        previewIsRequested = false
        applyChrome()
    }

    private func revealControls() {
        setControlsVisible(playerState.phase != .idle && playerState.phase != .resolving)
        hideTask?.cancel()
        guard playerState.phase == .ready, !playerState.isPaused else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, let self, !self.pointerIsOverControls else { return }
            self.setControlsVisible(false)
        }
    }

    private func setControlsVisible(_ visible: Bool) {
        guard chromeIsVisible != visible else { return }
        chromeIsVisible = visible
        applyChrome()
        onChromeVisibilityChange?(visible)
    }

    /// Adds a view to the chrome and brings it straight to whatever the chrome is doing right now, so a view that
    /// joins late cannot start out contradicting the others.
    func registerChrome(_ view: NSView) {
        guard !chromeViews.contains(where: { $0 === view }) else { return }
        chromeViews.append(view)
        applyChrome()
    }

    /// Re-applies the current state to every chrome view. Anything that moves or rebuilds one of them calls this, so
    /// none can be left behind at an alpha that does not match what the chrome is doing.
    func refreshChrome() {
        applyChrome()
    }

    /// Brings every chrome view to what it should be right now. One pass over one list: there is no other way for any
    /// of them to change, so they cannot disagree with each other or with `chromeIsVisible`.
    private func applyChrome() {
        for view in chromeViews { fade(view, to: chromeTarget(for: view)) }
    }

    /// What a chrome view should be doing. All of it follows `chromeIsVisible`; the preview also has to have been
    /// asked for by the pointer, so the bubble follows the bar rather than only the pointer that summoned it.
    private func chromeTarget(for view: NSView) -> Bool {
        chromeIsVisible && (view !== preview || previewIsRequested)
    }

    /// Fades one chrome view to its target and keeps `isHidden` in step with where the fade actually ended: a view is
    /// hidden once it has reached alpha 0, and a fade in that overtakes a fade out leaves it visible and hit testing.
    /// This is the only code that writes `alphaValue` or `isHidden` on chrome, and it never writes one without the
    /// other — which is what makes an invisible view that still takes clicks unreachable.
    private func fade(_ view: NSView, to visible: Bool) {
        let target: CGFloat = visible ? 1 : 0
        // Already there, or already on its way there: re-animating would only restart the fade under the pointer.
        guard view.alphaValue != target || view.isHidden == visible else { return }
        // Unhidden before the fade in, or there would be nothing on screen for it to act on.
        if visible { view.isHidden = false }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = ChromeStyle.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            view.animator().alphaValue = visible ? 1 : 0
        } completionHandler: {
            // AppKit runs this on the main thread, but the handler itself is `@Sendable`, so the isolation has to be
            // stated rather than assumed by the compiler.
            MainActor.assumeIsolated {
                view.isHidden = view.alphaValue == 0
            }
        }
    }

    /// What the chrome is doing, which is not the same question as `controls.isHidden`: through a fade out the bar is
    /// still on screen and still hidden only at the end.
    private var chromeIsVisible = true

    /// The controls must not vanish from under the pointer that is about to click them.
    private var pointerIsOverControls: Bool {
        guard let window, !controls.isHidden else { return false }
        let point = controls.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return controls.bounds.contains(point)
    }

    private static func message(for phase: PlayerState.Phase) -> String? {
        switch phase {
        case .idle: "Paste a YouTube link with ⌘V"
        case .resolving: "Finding streams…"
        case let .failed(reason): reason
        case .loading, .ready, .ended: nil
        }
    }
}

extension KeyPress {
    /// Arrow keys by key code; everything else by its characters ignoring modifiers.
    init?(event: NSEvent) {
        let key: Key
        switch event.keyCode {
        case 123: key = .leftArrow
        case 124: key = .rightArrow
        case 125: key = .downArrow
        case 126: key = .upArrow
        default:
            guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return nil }
            key = .character(characters)
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        self.init(key, modifiers: modifiers)
    }
}
