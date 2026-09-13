import AppKit
import CueMPV
import CuePlayer

/// The window's content: video, a status message and the controls overlay. Turns key events into `KeyPress`es.
final class PlayerView: NSView {
    let videoView: VideoView
    let controls = ControlsView()
    let preview = PreviewPopover()
    var onKeyPress: ((KeyPress) -> Bool)?
    /// Called whenever the controls appear or disappear, so the window can fade its title bar with them.
    var onChromeVisibilityChange: ((Bool) -> Void)?
    /// Chrome that belongs to the window rather than to this view — the sidebar button, which sits in the container
    /// around the video — and has to come and go with the controls instead of lingering over a bare picture.
    weak var companionChrome: NSView? {
        didSet {
            companionChrome?.alphaValue = chromeIsVisible ? 1 : 0
            companionChrome?.isHidden = !chromeIsVisible
        }
    }

    private let messageLabel = NSTextField(labelWithString: "")
    private var playerState = PlayerState()
    private var timeline = ChapterTimeline(chapters: [], duration: nil)
    private var hideTask: Task<Void, Never>?
    private var previewLeadingConstraint: NSLayoutConstraint!
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

        for view in [videoView, messageLabel, controls, preview] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
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
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        revealControls()
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
        let fading = [controls, companionChrome].compactMap { $0 }
        if visible {
            // Unhidden before the fade, or there would be nothing on screen for it to act on.
            for view in fading {
                view.alphaValue = 0
                view.isHidden = false
            }
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = ChromeStyle.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for view in fading {
                view.animator().alphaValue = visible ? 1 : 0
            }
        } completionHandler: { [weak self] in
            // AppKit runs this on the main thread, but the handler itself is `@Sendable`, so the isolation has to be
            // stated rather than assumed by the compiler. Nothing is captured but `self`.
            MainActor.assumeIsolated {
                // Hidden only once it has actually faded, so it keeps hit-testing until it is gone — and not at all
                // if the pointer brought the chrome back while the fade was still running.
                guard let self, !self.chromeIsVisible else { return }
                self.controls.isHidden = true
                self.companionChrome?.isHidden = true
            }
        }
        onChromeVisibilityChange?(visible)
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
