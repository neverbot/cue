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

    private let messageLabel = NSTextField(labelWithString: "")
    private var playerState = PlayerState()
    private var timeline = ChapterTimeline(chapters: [], duration: nil)
    private var hideTask: Task<Void, Never>?
    private var previewLeadingConstraint: NSLayoutConstraint!

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
        guard controls.isHidden == visible else { return }
        controls.isHidden = !visible
        onChromeVisibilityChange?(visible)
    }

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
