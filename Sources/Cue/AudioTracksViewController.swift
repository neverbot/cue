import AppKit
import CueQueue

/// Lists the audio languages a dubbed video offers. The third page of the trailing inspector: it owns a list and an
/// empty state, and nothing about where it is shown or about what choosing a row does.
///
/// It holds no logic of its own. `AudioTrackPresentation` decides what is listed and which row is marked, and
/// `AudioTrackSession` decides what the player is told.
final class AudioTracksViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    /// The id of the track the user picked.
    var onSelect: ((String) -> Void)?

    private let tableView = NSTableView()
    /// Shown instead of the list when the video has one soundtrack, the way the chapters page says it has no
    /// chapters. A list with a single row would offer a choice that does not exist.
    private let emptyLabel = NSTextField(labelWithString: AudioTrackPresentation.singleTrackMessage)
    private var rows: [AudioTrackRow] = []

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("audioTrack"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .inset
        // The height the subtitles page gives a track row, so the two lists of tracks read as one thing.
        tableView.rowHeight = 24
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        emptyLabel.alignment = .center
        // The size the queue's rows are set in, so the two columns state things in the same voice.
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true

        let content = NSView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scrollView)
        content.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -16),
        ])
        view = content
    }

    /// An empty list is a video with nothing to choose between, which is what the empty state is for: emptiness is
    /// read from the rows, never from a count this page works out for itself.
    func setRows(_ rows: [AudioTrackRow]) {
        self.rows = rows
        tableView.reloadData()
        let isEmpty = rows.isEmpty
        emptyLabel.isHidden = !isEmpty
        tableView.enclosingScrollView?.isHidden = isEmpty
        guard let selected = AudioTrackPresentation.selectedRow(in: rows) else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
    }

    @objc private func rowClicked() {
        let row = tableView.selectedRow
        guard rows.indices.contains(row) else { return }
        onSelect?(rows[row].id)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        rows[row].title
    }
}
