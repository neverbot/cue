import AppKit
import CueQueue

/// One sidebar row. The same view serves all three display modes: the thumbnail and the second line are hidden in
/// the modes that do not show them, so switching modes needs no second cell type.
final class QueueRowView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("QueueRow")
    static let thumbnailWidth: CGFloat = 106

    /// The ground under the video playing right now. Bold type alone only showed while comparing one row against
    /// another; a tinted ground says it at a glance. The accent is the right colour by the system's own rule — it
    /// marks what is active and nothing else — and it is drawn rather than set on a layer, so it re-resolves when
    /// the appearance or the chosen accent changes instead of freezing whatever was current at build time.
    private let nowPlayingFill = NowPlayingFill()
    private let thumbnail = NSImageView()
    /// Marks a video already watched, or the one playing now. A glyph rather than a colour: dimming was the only
    /// signal this list had, and it was already spoken for by a title that is not known yet, so the two states were
    /// drawn identically. Two facts that vary independently need two channels, and a symbol also says it without
    /// relying on colour at all.
    private let watchedMark = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let secondaryLabel = NSTextField(labelWithString: "")
    /// Title and second line as one block, so they are placed together rather than each finding its own height.
    /// A stack rather than two pinned labels because it drops a hidden arranged view out of the layout entirely:
    /// in compact mode the second line is hidden, and a plain subview would still claim its height and pull the
    /// block off centre.
    private let textStack = NSStackView()
    private let progressBar = NSView()
    private let progressFill = NSView()
    private var thumbnailWidthConstraint: NSLayoutConstraint!
    private var progressWidthConstraint: NSLayoutConstraint!
    private var watchedMarkWidthConstraint: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.wantsLayer = true
        thumbnail.layer?.cornerRadius = 4
        thumbnail.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor

        watchedMark.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Watched")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
        watchedMark.contentTintColor = .secondaryLabelColor
        watchedMark.imageScaling = .scaleNone

        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        secondaryLabel.font = .systemFont(ofSize: 10)
        secondaryLabel.textColor = .secondaryLabelColor
        secondaryLabel.lineBreakMode = .byTruncatingTail

        progressBar.wantsLayer = true
        progressBar.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        progressFill.wantsLayer = true
        progressFill.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        progressBar.addSubview(progressFill)

        textStack.orientation = .vertical
        // The two lines belong to each other: tight between them, and the row's own insets do the separating.
        textStack.alignment = .width
        textStack.spacing = 2
        textStack.setHuggingPriority(.required, for: .vertical)
        textStack.setViews([titleLabel, secondaryLabel], in: .top)

        for view in [nowPlayingFill, thumbnail, watchedMark, textStack, progressBar, progressFill] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        // First, so the whole row draws on top of it.
        addSubview(nowPlayingFill)
        addSubview(thumbnail)
        addSubview(watchedMark)
        addSubview(textStack)
        addSubview(progressBar)

        thumbnailWidthConstraint = thumbnail.widthAnchor.constraint(equalToConstant: Self.thumbnailWidth)
        progressWidthConstraint = progressFill.widthAnchor.constraint(equalToConstant: 0)
        // Collapses to nothing on a row that is not watched, so an unwatched row's title starts exactly where it
        // always did and the mark costs no space it is not using.
        watchedMarkWidthConstraint = watchedMark.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            // Inset a little, so the rounded ground sits inside the row rather than running edge to edge into the
            // selection highlight an inset-style table draws around it.
            nowPlayingFill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            nowPlayingFill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            nowPlayingFill.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            nowPlayingFill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

            thumbnail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            thumbnail.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailWidthConstraint,
            thumbnail.heightAnchor.constraint(equalTo: thumbnail.widthAnchor, multiplier: 9.0 / 16.0),

            watchedMark.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 8),
            watchedMark.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
            watchedMarkWidthConstraint,

            textStack.leadingAnchor.constraint(equalTo: watchedMark.trailingAnchor, constant: 0),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            // Centred on the same line the thumbnail is centred on, so the two read as one object. The top inset
            // is the floor: a two-line title in a short row stops there and grows downwards rather than climbing
            // out of the row. Centring yields to it, and the bottom is only a preference, so nothing is ever
            // unsatisfiable.
            textStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 4),
            centring(textStack),
            preferring(textStack.bottomAnchor.constraint(lessThanOrEqualTo: progressBar.topAnchor, constant: -3)),

            progressBar.leadingAnchor.constraint(equalTo: textStack.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: textStack.trailingAnchor),
            progressBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            progressBar.heightAnchor.constraint(equalToConstant: 2),

            progressFill.leadingAnchor.constraint(equalTo: progressBar.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressBar.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressBar.bottomAnchor),
            progressWidthConstraint,
        ])
        textField = titleLabel
    }

    /// Centres the text block on the row, below the top inset's priority so a block too tall to centre sits under
    /// the inset instead of breaking the layout.
    private func centring(_ view: NSView) -> NSLayoutConstraint {
        let constraint = view.centerYAnchor.constraint(equalTo: centerYAnchor)
        constraint.priority = .defaultHigh
        return constraint
    }

    /// A constraint the layout honours when it can and drops when it cannot.
    private func preferring(_ constraint: NSLayoutConstraint) -> NSLayoutConstraint {
        constraint.priority = .defaultLow
        return constraint
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        applyProgressWidth()
    }

    private var progress: Double?

    func update(_ row: QueueRow, mode: QueueDisplayMode, image: NSImage?) {
        titleLabel.stringValue = row.title
        titleLabel.maximumNumberOfLines = mode == .compact ? 1 : 2
        titleLabel.font = row.isCurrent ? .boldSystemFont(ofSize: 12) : .systemFont(ofSize: 12)
        // Dimming now says one thing only: this title is not known yet, so what you are reading is the video's id
        // standing in for a name. Watched is the mark to the left. Folding both into this one colour made a watched
        // row with an unknown title, a watched row with a title, and a pending row with an unknown title all look
        // the same.
        titleLabel.textColor = row.isTitleKnown ? .labelColor : .secondaryLabelColor
        nowPlayingFill.isHidden = !row.isCurrent
        // A video can be both watched and playing again, and which one it is right now matters more than what it
        // once was, so the mark says "playing" whenever both are true.
        watchedMark.isHidden = !(row.isCurrent || row.isWatched)
        watchedMark.image = Self.mark(isCurrent: row.isCurrent)
        watchedMark.contentTintColor = row.isCurrent ? .controlAccentColor : .secondaryLabelColor
        watchedMarkWidthConstraint.constant = watchedMark.isHidden ? 0 : 15
        secondaryLabel.stringValue = row.secondaryText
        secondaryLabel.isHidden = mode == .compact || row.secondaryText.isEmpty
        thumbnail.isHidden = !row.showsThumbnail
        thumbnailWidthConstraint.constant = row.showsThumbnail ? Self.thumbnailWidth : 0
        thumbnail.image = row.showsThumbnail ? image : nil
        progress = row.progress
        progressBar.isHidden = row.progress == nil
        applyProgressWidth()
    }

    private func applyProgressWidth() {
        progressWidthConstraint.constant = progressBar.bounds.width * CGFloat(progress ?? 0)
    }

    private static func mark(isCurrent: Bool) -> NSImage? {
        let name = isCurrent ? "speaker.wave.2.fill" : "checkmark.circle.fill"
        let label = isCurrent ? "Playing now" : "Watched"
        return NSImage(systemSymbolName: name, accessibilityDescription: label)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
    }
}

/// The ground under the row playing right now: the system accent, kept faint enough to read behind text.
///
/// Drawn rather than assigned to a layer's `backgroundColor`, for the same reason the sidebar's own floating ground
/// is: a `cgColor` is resolved once and then frozen, so it would keep the appearance and the accent colour that were
/// in force when the row was built instead of following the ones in force now.
final class NowPlayingFill: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let rounded = NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5)
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        rounded.fill()
    }
}
