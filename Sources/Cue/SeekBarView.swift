import AppKit
import CuePlayer

/// The seek bar: a drawn track with the elapsed fill, chapter ticks and a knob.
///
/// A drawn view rather than an `NSSlider` because a slider can neither mark chapters on its track nor report where the
/// pointer is hovering — and the previews are entirely about where the pointer is. Every number here comes from
/// `SeekBarGeometry`, which is tested; this class only paints.
final class SeekBarView: NSView {
    static let trackHeight: CGFloat = 4
    static let knobRadius: CGFloat = 6
    static let height: CGFloat = 20

    var duration: Double? { didSet { needsDisplay = true } }
    var position = 0.0 { didSet { if !isScrubbing { needsDisplay = true } } }
    /// How far ahead the stream has loaded, in media time. Drawn as a lighter band behind the elapsed fill, so on a
    /// slow connection it is visible how much a pause has banked.
    var bufferedUntil: Double? { didSet { if bufferedUntil != oldValue { needsDisplay = true } } }
    /// Where chapters begin, as fractions of the duration.
    var chapterFractions: [Double] = [] { didSet { needsDisplay = true } }
    var isEnabled = true { didSet { needsDisplay = true } }

    /// Continuously while dragging, and once more with `isFinal` on mouse up.
    var onScrub: ((Double, Bool) -> Void)?
    /// The second under the pointer and its x in this view; nil seconds means the pointer left the bar.
    var onHover: ((Double?, CGFloat) -> Void)?

    private var isScrubbing = false
    private var scrubPosition = 0.0

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Self.height) }
    override var acceptsFirstResponder: Bool { false }

    /// The window is movable by its background, which is what lets the video be dragged to move the window. AppKit
    /// decides which views count as background by asking them this, and a plain `NSView` says yes — so dragging
    /// the seek bar scrubbed *and* moved the window at the same time. AppKit's own controls answer no already,
    /// which is why the volume slider and the buttons never had the problem.
    override var mouseDownCanMoveWindow: Bool { false }

    /// The knob has to fit at both ends, so the track is inset by its radius.
    private var trackWidth: CGFloat { max(bounds.width - Self.knobRadius * 2, 1) }
    private var shownPosition: Double { isScrubbing ? scrubPosition : position }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset = Self.knobRadius
        let y = (bounds.height - Self.trackHeight) / 2
        let radius = Self.trackHeight / 2

        NSColor.white.withAlphaComponent(0.25).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: inset, y: y, width: trackWidth, height: Self.trackHeight),
            xRadius: radius,
            yRadius: radius
        ).fill()

        if let bufferedUntil {
            let buffered = SeekBarGeometry.x(forSeconds: bufferedUntil, width: trackWidth, duration: duration)
            NSColor.white.withAlphaComponent(0.45).setFill()
            NSBezierPath(
                roundedRect: NSRect(x: inset, y: y, width: buffered, height: Self.trackHeight),
                xRadius: radius,
                yRadius: radius
            ).fill()
        }

        let progress = SeekBarGeometry.x(forSeconds: shownPosition, width: trackWidth, duration: duration)
        (isEnabled ? NSColor.controlAccentColor : NSColor.disabledControlTextColor).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: inset, y: y, width: progress, height: Self.trackHeight),
            xRadius: radius,
            yRadius: radius
        ).fill()

        NSColor.black.withAlphaComponent(0.6).setFill()
        for fraction in chapterFractions {
            let x = SeekBarGeometry.x(forFraction: fraction, width: trackWidth, inset: inset)
            NSBezierPath(rect: NSRect(x: x - 1, y: y - 2, width: 2, height: Self.trackHeight + 4)).fill()
        }

        guard isEnabled, duration != nil else { return }
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(
            x: inset + progress - Self.knobRadius,
            y: bounds.midY - Self.knobRadius,
            width: Self.knobRadius * 2,
            height: Self.knobRadius * 2
        )).fill()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let seconds = seconds(for: event) else { return }
        isScrubbing = true
        scrubPosition = seconds
        needsDisplay = true
        onScrub?(seconds, false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isScrubbing, let seconds = seconds(for: event) else { return }
        scrubPosition = seconds
        needsDisplay = true
        onScrub?(seconds, false)
        onHover?(seconds, point(for: event).x)
    }

    override func mouseUp(with event: NSEvent) {
        guard isScrubbing else { return }
        isScrubbing = false
        let seconds = seconds(for: event) ?? scrubPosition
        position = seconds
        onScrub?(seconds, true)
    }

    override func mouseMoved(with event: NSEvent) {
        onHover?(seconds(for: event), point(for: event).x)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(nil, 0)
    }

    private func point(for event: NSEvent) -> NSPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func seconds(for event: NSEvent) -> Double? {
        SeekBarGeometry.seconds(atX: point(for: event).x - Self.knobRadius, width: trackWidth, duration: duration)
    }
}
