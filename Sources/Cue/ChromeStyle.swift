import AppKit

/// The look shared by every floating element drawn over the video: the controls bar and the seek preview.
///
/// These are plain fills rather than vibrancy. `NSVisualEffectView` blurs what is behind it *inside* the window, and
/// the video is a GPU-backed layer that vibrancy cannot sample: with nothing to blur, the material collapses to its
/// flat fill. A translucent dark fill over the video is honest about what it is and looks the same everywhere.
enum ChromeStyle {
    /// A dark neutral tinted slightly blue. Not pure black: over a dark scene a black panel disappears, and a hint
    /// of blue keeps it reading as chrome rather than as a hole in the picture.
    static let fill = NSColor(srgbRed: 0.07, green: 0.075, blue: 0.09, alpha: 0.62)

    /// A hairline that keeps the edge legible against a bright frame.
    static let border = NSColor(white: 1, alpha: 0.10)
    static let borderWidth: CGFloat = 1

    /// Corner radii: the bar is the larger element, the preview the smaller one.
    static let controlsCornerRadius: CGFloat = 12
    static let previewCornerRadius: CGFloat = 8

    /// How long the chrome takes to fade in or out.
    static let fadeDuration: TimeInterval = 0.18

    /// Applies the fill, the hairline and the rounded corners to a view's own layer.
    static func applyPanel(to view: NSView, cornerRadius: CGFloat) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        layer.backgroundColor = fill.cgColor
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = borderWidth
        layer.borderColor = border.cgColor
    }

    /// A soft drop shadow, so the bar separates from a bright scene. Only the controls bar takes one: the preview
    /// already sits above the bar and would stack two shadows in the same place.
    static func applyShadow(to view: NSView) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        layer.masksToBounds = false
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: -2)
    }
}
