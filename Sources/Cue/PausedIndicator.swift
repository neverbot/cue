import AppKit

/// A play glyph over the middle of the picture while playback is paused, so a still frame is never mistaken for a
/// stalled one. It appears only with a video loaded and paused: while the player is idle, resolving, loading or
/// failed the centre belongs to the status message, which has something to say that this does not.
///
/// Chrome like the rest: the same translucent fill and hairline, the same fade, and no shadow — the controls bar is
/// the only element in the app that takes one.
final class PausedIndicator: NSView {
    private static let diameter: CGFloat = 68

    /// What the view is being asked to be, which through a fade is not yet what it looks like.
    private var isShown = false

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter))
        ChromeStyle.applyPanel(to: self, cornerRadius: Self.diameter / 2)
        alphaValue = 0
        isHidden = true
        setAccessibilityLabel("Paused")

        let glyph = NSImageView(image: NSImage(
            systemSymbolName: "play.fill",
            accessibilityDescription: "Paused"
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 28, weight: .medium)) ?? NSImage())
        glyph.contentTintColor = .white
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.diameter),
            heightAnchor.constraint(equalToConstant: Self.diameter),
            // A triangle carries its weight to the left of the box it is drawn in, so it is nudged right to sit
            // optically in the middle of the circle rather than geometrically in it.
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 2),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Transparent to the mouse. Clicking the picture toggles playback, and this sits exactly where someone reaches to
    /// resume: taking the click would either swallow it or, forwarded, toggle twice. The click belongs to the video.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setVisible(_ visible: Bool) {
        guard isShown != visible else { return }
        isShown = visible
        // Unhidden before the fade in, or there would be nothing on screen for it to act on.
        if visible { isHidden = false }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = ChromeStyle.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = visible ? 1 : 0
        } completionHandler: { [weak self] in
            // AppKit runs this on the main thread, but the handler is `@Sendable`, so the isolation is stated rather
            // than assumed by the compiler.
            MainActor.assumeIsolated {
                guard let self, !self.isShown else { return }
                self.isHidden = true
            }
        }
    }
}
