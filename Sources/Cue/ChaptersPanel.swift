import AppKit
import CueCore
import CuePlayer

/// Lists a video's chapters. A utility panel rather than a second sidebar: the queue owns the sidebar, and a 960-point
/// window cannot afford two columns.
final class ChaptersPanelController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    var onSelect: ((Double) -> Void)?

    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "This video has no chapters.")
    private var chapters: [Chapter] = []
    private var currentIndex: Int?

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 360),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Chapters"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("chapter"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .inset
        tableView.rowHeight = 28
        tableView.allowsMultipleSelection = false

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        emptyLabel.alignment = .center
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
        panel.contentView = content

        super.init(window: panel)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setChapters(_ chapters: [Chapter]) {
        self.chapters = chapters
        currentIndex = nil
        tableView.reloadData()
        let isEmpty = chapters.isEmpty
        emptyLabel.isHidden = !isEmpty
        tableView.enclosingScrollView?.isHidden = isEmpty
    }

    /// Marks the chapter playing now, without disturbing a selection the user is making.
    func setCurrent(_ index: Int?) {
        guard index != currentIndex else { return }
        currentIndex = index
        tableView.reloadData()
    }

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard chapters.indices.contains(row) else { return }
        onSelect?(chapters[row].start)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { chapters.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("ChapterRow")
        let view = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? Self.makeRow(identifier)
        let chapter = chapters[row]
        view.textField?.stringValue = chapter.title
        view.textField?.font = row == currentIndex ? .boldSystemFont(ofSize: 12) : .systemFont(ofSize: 12)
        (view.viewWithTag(1) as? NSTextField)?.stringValue = PlaybackTime.format(chapter.start)
        return view
    }

    private static func makeRow(_ identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let view = NSTableCellView()
        view.identifier = identifier
        let title = NSTextField(labelWithString: "")
        title.lineBreakMode = .byTruncatingTail
        let time = NSTextField(labelWithString: "")
        time.tag = 1
        time.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        time.textColor = .secondaryLabelColor
        for label in [time, title] {
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
        }
        NSLayoutConstraint.activate([
            time.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            time.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            time.widthAnchor.constraint(equalToConstant: 52),
            title.leadingAnchor.constraint(equalTo: time.trailingAnchor, constant: 6),
            title.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            title.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        view.textField = title
        return view
    }
}
