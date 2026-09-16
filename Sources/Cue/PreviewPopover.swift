import AppKit
import CueCore
import CuePlayer

/// The preview shown while the pointer is over the seek bar: one storyboard tile, the time under it and the chapter
/// it falls in. A plain view rather than an `NSPopover`: a popover would take focus and animate, and this has to keep
/// up with a pointer.
final class PreviewPopover: NSView {
    static let imageWidth: CGFloat = 168

    /// Chrome, not background: it hangs directly over the seek bar, so a click that lands on the bubble instead of
    /// the bar must not start dragging the window. Same reason as `ControlsView` and `SeekBarView`.
    override var mouseDownCanMoveWindow: Bool { false }

    private let imageView = NSImageView()
    private let timeLabel = NSTextField(labelWithString: "0:00")
    private let chapterLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        ChromeStyle.applyPanel(to: self, cornerRadius: ChromeStyle.previewCornerRadius)
        alphaValue = 0
        isHidden = true

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 4
        imageView.layer?.backgroundColor = NSColor.black.cgColor
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        timeLabel.textColor = .white
        timeLabel.alignment = .center
        chapterLabel.font = .systemFont(ofSize: 10)
        chapterLabel.textColor = .white.withAlphaComponent(0.75)
        chapterLabel.alignment = .center
        chapterLabel.lineBreakMode = .byTruncatingTail

        let column = NSStackView(views: [imageView, timeLabel, chapterLabel])
        column.orientation = .vertical
        column.spacing = 2
        column.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.widthAnchor.constraint(equalToConstant: Self.imageWidth),
            imageView.heightAnchor.constraint(equalToConstant: (Self.imageWidth * 9 / 16).rounded(.down)),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Fills in what the bubble says. Whether it is on screen at all is not its own decision: the player view owns
    /// that, together with the rest of the chrome, so the bubble cannot outlive the bar it hangs over.
    func update(seconds: Double, chapter: String?, image: NSImage?) {
        timeLabel.stringValue = PlaybackTime.format(seconds)
        chapterLabel.stringValue = chapter ?? ""
        chapterLabel.isHidden = chapter == nil
        if let image { imageView.image = image }
    }

    /// Drops the frame, so the next hover never flashes the last one before its own sheet arrives.
    func clear() {
        imageView.image = nil
    }

    /// One tile out of a sheet. The sheet's rows run downwards while AppKit's coordinates run upwards, which is the
    /// only reason this is not a straight crop.
    static func tile(_ frame: StoryboardSpec.Frame, from data: Data) -> NSImage? {
        guard let sheet = NSImage(data: data),
              let bitmap = sheet.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
              bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else { return nil }
        // An NSImage sizes itself in points, from whatever DPI the file claims, while the storyboard spec's offsets
        // are pixels. Pinning the image to its pixel dimensions keeps the crop arithmetic in one unit.
        sheet.size = NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        let source = NSRect(
            x: CGFloat(frame.originX),
            y: CGFloat(bitmap.pixelsHigh) - CGFloat(frame.originY + frame.height),
            width: CGFloat(frame.width),
            height: CGFloat(frame.height)
        )
        let tile = NSImage(size: NSSize(width: frame.width, height: frame.height))
        tile.lockFocus()
        sheet.draw(in: NSRect(origin: .zero, size: tile.size), from: source, operation: .copy, fraction: 1)
        tile.unlockFocus()
        return tile
    }
}
