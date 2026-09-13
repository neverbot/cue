import AppKit
import CuePlayer

/// The mini player: a small floating window that borrows the player view.
///
/// Picture-in-Picture cannot be used here — the public API drives `AVPlayerLayer` and `AVSampleBufferDisplayLayer`,
/// and Cue's video is an OpenGL layer fed by libmpv's render API — so the video is moved instead of mirrored. The view
/// that moves is the same instance both ways: it must never be recreated, because its render context is mpv's only one.
final class MiniPlayerWindowController: NSWindowController, NSWindowDelegate {
    /// Called when the window is closed by its button rather than by the toggle.
    var onClose: (() -> Void)?

    /// The video's shape, which the window keeps while it is resized.
    private let aspectRatio: Double

    init(contentSize: CGSize, aspectRatio: Double) {
        self.aspectRatio = aspectRatio > 0 ? aspectRatio : 16.0 / 9.0
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Cue"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.isRestorable = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentMinSize = CGSize(
            width: MiniPlayerGeometry.minimumWidth,
            height: MiniPlayerGeometry.minimumWidth / CGFloat(self.aspectRatio)
        )
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Puts `view` in this window, filling it.
    func adopt(_ view: NSView) {
        guard let content = window?.contentView else { return }
        MiniPlayerWindowController.pin(view, into: content)
    }

    /// Moves a view into a container, edge to edge. Used in both directions, so the hand-off is symmetrical.
    static func pin(_ view: NSView, into container: NSView) {
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    /// Keeps the video's proportions during a live resize: the user drags the width, the height follows. The rule
    /// itself lives in `MiniPlayerGeometry`, so it can be argued with in tests rather than on screen.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let visible = (sender.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(origin: .zero, size: frameSize)
        let proposed = NSRect(origin: sender.frame.origin, size: frameSize)
        let content = MiniPlayerGeometry.resized(
            toWidth: sender.contentRect(forFrameRect: proposed).width,
            aspectRatio: aspectRatio,
            visibleFrame: visible
        )
        return sender.frameRect(forContentRect: NSRect(origin: sender.frame.origin, size: content)).size
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
