import AppKit

/// A spinner over the middle of the picture while Cue is finding a stream, opening it, or waiting on the network.
///
/// The same circle, fill, hairline and fade as `PausedIndicator`, in the same place: these two are the same thing
/// said about different states, and a viewer should not have to learn two vocabularies for the centre of the
/// window. Only ever one of them is on screen — `PlayerIndicator` decides which.
final class LoadingIndicator: NSView {
    private static let diameter: CGFloat = 68

    /// What the view is being asked to be, which through a fade is not yet what it looks like.
    private var isShown = false
    private let spinner = NSProgressIndicator()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter))
        ChromeStyle.applyPanel(to: self, cornerRadius: Self.diameter / 2)
        alphaValue = 0
        isHidden = true
        setAccessibilityLabel("Loading")

        spinner.style = .spinning
        spinner.controlSize = .large
        spinner.isIndeterminate = true
        // It sits on an explicit dark fill over the video, not on the window's material, so it takes the light
        // appearance's white rather than following whatever the system theme would give it.
        spinner.appearance = NSAppearance(named: .darkAqua)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.diameter),
            heightAnchor.constraint(equalToConstant: Self.diameter),
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Transparent to the mouse, like the paused glyph: clicking the picture toggles playback, and this sits where
    /// someone reaches to do it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setVisible(_ visible: Bool) {
        guard isShown != visible else { return }
        isShown = visible
        if visible {
            isHidden = false
            // Animating only while it is on screen: a spinner left running behind an invisible view redraws
            // forever, and this app is meant to be cheap to leave open.
            spinner.startAnimation(nil)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = ChromeStyle.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = visible ? 1 : 0
        } completionHandler: { [weak self] in
            // AppKit runs this on the main thread, but the handler is `@Sendable`, so the isolation is stated
            // rather than assumed by the compiler.
            MainActor.assumeIsolated {
                guard let self, !self.isShown else { return }
                self.isHidden = true
                self.spinner.stopAnimation(nil)
            }
        }
    }
}
