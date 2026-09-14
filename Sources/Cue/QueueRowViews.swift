import AppKit
import CueQueue

/// One sidebar row. The same view serves all three display modes: the thumbnail and the second line are hidden in
/// the modes that do not show them, so switching modes needs no second cell type.
final class QueueRowView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("QueueRow")
    static let thumbnailWidth: CGFloat = 106

    private let thumbnail = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let secondaryLabel = NSTextField(labelWithString: "")
    private let progressBar = NSView()
    private let progressFill = NSView()
    private var thumbnailWidthConstraint: NSLayoutConstraint!
    private var progressWidthConstraint: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.wantsLayer = true
        thumbnail.layer?.cornerRadius = 4
        thumbnail.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor

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

        for view in [thumbnail, titleLabel, secondaryLabel, progressBar, progressFill] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        addSubview(thumbnail)
        addSubview(titleLabel)
        addSubview(secondaryLabel)
        addSubview(progressBar)

        thumbnailWidthConstraint = thumbnail.widthAnchor.constraint(equalToConstant: Self.thumbnailWidth)
        progressWidthConstraint = progressFill.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            thumbnail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            thumbnail.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbnailWidthConstraint,
            thumbnail.heightAnchor.constraint(equalTo: thumbnail.widthAnchor, multiplier: 9.0 / 16.0),

            titleLabel.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),

            secondaryLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            secondaryLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            secondaryLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),

            progressBar.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            progressBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            progressBar.heightAnchor.constraint(equalToConstant: 2),

            progressFill.leadingAnchor.constraint(equalTo: progressBar.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressBar.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressBar.bottomAnchor),
            progressWidthConstraint,
        ])
        textField = titleLabel
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
        // A title that is not known yet is the video's id standing in for one, and it is drawn in the secondary
        // label colour so it reads as provisional rather than as the video's name - the same colour a watched row's
        // title takes, which is the one dimmed treatment this list has.
        titleLabel.textColor = row.isTitleKnown && !row.isWatched ? .labelColor : .secondaryLabelColor
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
}
