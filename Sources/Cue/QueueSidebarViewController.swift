import AppKit
import CueCore
import CueQueue
import os

/// The queue sidebar: a counter, a display-mode control and one table view that draws all three modes. Every decision
/// about what a row says lives in `CueQueue`'s `QueuePresentation`; this class only draws it and forwards actions.
final class QueueSidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    /// The internal drag type, so reordering is told apart from a link dropped from a browser.
    static let rowType = NSPasteboard.PasteboardType("com.neverbot.cue.queue-row")
    static let width: CGFloat = 280
    /// How many decoded images to keep in memory. The bytes stay in `ThumbnailStore`'s disk cache, so dropping one
    /// costs a file read, not a download.
    static let imageCacheLimit = 120

    var onPlay: ((VideoID) -> Void)?
    /// Called after the sidebar itself changed the queue, so the rest of the window can catch up.
    var onQueueChange: (() -> Void)?

    private(set) var mode: QueueDisplayMode = .list
    private var rows: [QueueRow] = []
    private var currentVideoID: VideoID?

    private let store: QueueStore
    private let thumbnails: ThumbnailStore
    private let counterLabel = NSTextField(labelWithString: "Queue empty")
    private let modeButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    /// Decoded thumbnails, newest last in `imageOrder`, capped at `imageCacheLimit`.
    private var images: [String: NSImage] = [:]
    private var imageOrder: [String] = []
    private var requestedImages: Set<String> = []
    private let logger = Logger(subsystem: "com.neverbot.cue", category: "queue")

    init(store: QueueStore, thumbnails: ThumbnailStore) {
        self.store = store
        self.thumbnails = thumbnails
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: Self.width, height: 400))

        counterLabel.font = .systemFont(ofSize: 11)
        counterLabel.textColor = .secondaryLabelColor

        modeButton.addItems(withTitles: QueueDisplayMode.allCases.map(\.title))
        modeButton.target = self
        modeButton.action = #selector(changeMode(_:))
        modeButton.controlSize = .small
        modeButton.font = .systemFont(ofSize: 11)
        modeButton.isBordered = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("video"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .inset
        tableView.rowHeight = mode.rowHeight
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(playSelectedRow)
        tableView.allowsMultipleSelection = true
        tableView.menu = makeContextMenu()
        tableView.registerForDraggedTypes([Self.rowType, .string, .URL])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let header = NSStackView(views: [counterLabel, NSView(), modeButton])
        header.orientation = .horizontal
        header.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 6)

        for view in [header, scrollView] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Scrolling brings new rows into view, and only those rows' thumbnails are worth fetching. Registering with
        // a selector rather than a block keeps no token to release: the notification centre holds a zeroing weak
        // reference to the observer, so there is nothing to undo in a deinit.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(visibleRowsChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        reload()
    }

    @objc private func visibleRowsChanged() {
        loadVisibleThumbnails()
    }

    // MARK: - Contents

    /// Re-reads the queue and redraws. Cheap enough to call on every change: a personal queue is hundreds of rows.
    func reload() {
        let videos = (try? store.videos()) ?? []
        rows = QueuePresentation.rows(for: videos, mode: mode, current: currentVideoID)
        counterLabel.stringValue = QueuePresentation.counterText(for: (try? store.summary()) ?? QueueSummary())
        tableView.rowHeight = mode.rowHeight
        tableView.reloadData()
        if mode.showsThumbnail { loadVisibleThumbnails() }
    }

    func setCurrentVideo(_ videoID: VideoID?) {
        currentVideoID = videoID
        reload()
    }

    func setMode(_ newMode: QueueDisplayMode) {
        mode = newMode
        modeButton.selectItem(at: QueueDisplayMode.allCases.firstIndex(of: newMode) ?? 0)
        reload()
    }

    @objc private func changeMode(_ sender: NSPopUpButton) {
        let modes = QueueDisplayMode.allCases
        setMode(modes[min(max(sender.indexOfSelectedItem, 0), modes.count - 1)])
    }

    // MARK: - Actions

    @objc private func playSelectedRow() {
        guard let videoID = selectedVideoIDs().first else { return }
        onPlay?(videoID)
    }

    @objc private func removeSelectedRows() {
        change { store in
            for videoID in selectedVideoIDs() {
                try store.remove(videoID)
            }
        }
    }

    @objc private func markSelectedWatched() {
        change { store in
            for videoID in selectedVideoIDs() {
                try store.markWatched(videoID)
            }
        }
    }

    @objc private func markSelectedUnwatched() {
        change { store in
            for videoID in selectedVideoIDs() {
                try store.markUnwatched(videoID)
            }
        }
    }

    @objc private func copySelectedLinks() {
        let links = selectedVideoIDs().map { AddRequest.watchURL(for: $0).absoluteString }
        guard !links.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(links.joined(separator: "\n"), forType: .string)
    }

    override func keyDown(with event: NSEvent) {
        // Delete and forward delete remove the selection; everything else goes to the player's bindings.
        if event.keyCode == 51 || event.keyCode == 117 {
            removeSelectedRows()
            return
        }
        super.keyDown(with: event)
    }

    private func selectedVideoIDs() -> [VideoID] {
        tableView.selectedRowIndexes.compactMap { index in
            rows.indices.contains(index) ? VideoID(rows[index].videoID) : nil
        }
    }

    private func change(_ work: (QueueStore) throws -> Void) {
        do {
            try work(store)
        } catch {
            logger.error("Queue database error: \(String(describing: error), privacy: .public)")
        }
        reload()
        onQueueChange?()
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Play", action: #selector(playSelectedRow), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Mark as Watched", action: #selector(markSelectedWatched), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Mark as Unwatched", action: #selector(markSelectedUnwatched), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Copy Link", action: #selector(copySelectedLinks), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Remove from Queue", action: #selector(removeSelectedRows), keyEquivalent: ""))
        for item in menu.items {
            item.target = self
        }
        return menu
    }

    // MARK: - Thumbnails

    /// Fetches only what is on screen. A queue of hundreds must not start hundreds of requests because the sidebar
    /// was switched to thumbnail mode.
    private func loadVisibleThumbnails() {
        guard mode.showsThumbnail else { return }
        let visible = tableView.rows(in: tableView.visibleRect)
        guard visible.length > 0 else { return }
        for row in visible.location..<(visible.location + visible.length) where rows.indices.contains(row) {
            let identifier = rows[row].videoID
            guard images[identifier] == nil, !requestedImages.contains(identifier),
                  let videoID = VideoID(identifier) else { continue }
            requestedImages.insert(identifier)
            Task { [weak self, thumbnails] in
                guard let data = try? await thumbnails.imageData(for: videoID), let image = NSImage(data: data) else { return }
                self?.keep(image, for: videoID.rawValue)
            }
        }
    }

    /// Stores one decoded image and redraws only its row.
    private func keep(_ image: NSImage, for identifier: String) {
        images[identifier] = image
        imageOrder.append(identifier)
        while imageOrder.count > Self.imageCacheLimit {
            let dropped = imageOrder.removeFirst()
            guard dropped != identifier else { continue }
            images[dropped] = nil
            requestedImages.remove(dropped)
        }
        guard let row = rows.firstIndex(where: { $0.videoID == identifier }) else { return }
        tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let cell = tableView.makeView(withIdentifier: QueueRowView.reuseIdentifier, owner: self) as? QueueRowView
            ?? {
                let created = QueueRowView(frame: .zero)
                created.identifier = QueueRowView.reuseIdentifier
                return created
            }()
        cell.update(rows[row], mode: mode, image: images[rows[row].videoID])
        return cell
    }

    // MARK: - Drag and drop

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard rows.indices.contains(row), let videoID = VideoID(rows[row].videoID) else { return nil }
        let item = NSPasteboardItem()
        item.setString(videoID.rawValue, forType: Self.rowType)
        item.setString(AddRequest.watchURL(for: videoID).absoluteString, forType: .string)
        return item
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: any NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard dropOperation == .above else { return [] }
        return info.draggingSource as? NSTableView === tableView ? .move : .copy
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: any NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        let pasteboard = info.draggingPasteboard
        if let moved = pasteboard.string(forType: Self.rowType), let videoID = VideoID(moved) {
            change { store in try store.move(videoID, to: row) }
            return true
        }
        let dropped = (pasteboard.readObjects(forClasses: [NSURL.self, NSString.self]) ?? []).map { String(describing: $0) }
        let videoIDs = AddRequest.videoIDs(inDropped: dropped)
        guard !videoIDs.isEmpty else {
            NSSound.beep()
            return false
        }
        change { store in
            for (offset, videoID) in videoIDs.enumerated() {
                if try store.add(videoID) {
                    try store.move(videoID, to: row + offset)
                }
            }
        }
        return true
    }
}
