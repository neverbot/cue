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
    /// Called whenever the mode changes, by the popup here or by the menu, so the window can remember it.
    var onModeChange: ((QueueDisplayMode) -> Void)?
    /// Called with a file dropped on the queue. The sidebar does not import it itself: a file is a question for the
    /// window to ask before anything changes.
    var onFileDrop: ((URL) -> Void)?

    private(set) var mode: QueueDisplayMode
    private var rows: [QueueRow] = []
    private var currentVideoID: VideoID?

    private let store: QueueStore
    private let thumbnails: ThumbnailStore
    private let summaries: any VideoSummarising
    private let counterLabel = NSTextField(labelWithString: "Queue empty")
    private let modeButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    /// The ground the queue is drawn on while it sits beside the video. `NSVisualEffectView` with the sidebar
    /// material is the platform's own surface for a column next to the content, and it resolves light and dark by
    /// itself. Before it, nothing painted here at all and the window's black showed through: passable as a design in
    /// the dark appearance, and the reason the light one looked like it did nothing.
    private let surface = NSVisualEffectView()
    /// What the queue is drawn on instead while it floats over the picture. See `setFloatingOverVideo(_:)`.
    private let overlayFill = SidebarOverlayFill()
    /// Decoded thumbnails, newest last in `imageOrder`, capped at `imageCacheLimit`.
    private var images: [String: NSImage] = [:]
    private var imageOrder: [String] = []
    private var requestedImages: Set<String> = []
    /// Videos already asked about, whatever the answer was. One question per video per session.
    private var requestedTitles: Set<String> = []
    /// Videos still waiting to be named, in the order they came on screen.
    private var pendingTitles: [VideoID] = []
    /// The one task draining `pendingTitles`. Nil when nothing is being fetched.
    private var titleTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.neverbot.cue", category: "queue")

    /// The mode is handed in rather than set afterwards, so the restored one is in place before the view is built and
    /// the popup is never briefly showing a mode the table is not drawing.
    init(
        store: QueueStore,
        thumbnails: ThumbnailStore,
        mode: QueueDisplayMode = .list,
        summaries: any VideoSummarising = OEmbedSummaries()
    ) {
        self.store = store
        self.thumbnails = thumbnails
        self.mode = mode
        self.summaries = summaries
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
        modeButton.selectItem(at: QueueDisplayMode.allCases.firstIndex(of: mode) ?? 0)
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
        tableView.registerForDraggedTypes([Self.rowType, .string, .URL, .fileURL])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let header = NSStackView(views: [counterLabel, NSView(), modeButton])
        header.orientation = .horizontal
        header.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 6)

        surface.material = .sidebar
        surface.blendingMode = .behindWindow
        surface.state = .followsWindowActiveState
        overlayFill.isHidden = true

        // The two grounds go in first, so everything the queue draws sits on top of whichever one is showing.
        for view in [surface, overlayFill, header, scrollView] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        for ground in [surface, overlayFill] as [NSView] {
            NSLayoutConstraint.activate([
                ground.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                ground.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                ground.topAnchor.constraint(equalTo: container.topAnchor),
                ground.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            // The window draws its content full size under a transparent title bar, so the plain top anchor puts the
            // counter under the traffic lights. The safe area is what accounts for the title bar, and it stays right
            // in full screen and on any title bar height, which a hardcoded inset would not.
            header.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
        view = container
    }

    /// Which ground the queue is drawn on, decided by where it is hanging.
    ///
    /// Beside the video it is the platform's sidebar material, which follows the appearance on its own. Floating over
    /// the video it cannot be: that material blends with what is behind the *window*, so over the picture it would
    /// blur the desktop and read as a hole punched through the video. There the queue keeps the explicit 85 % window
    /// background it has always floated on.
    func setFloatingOverVideo(_ floating: Bool) {
        loadViewIfNeeded()
        surface.isHidden = floating
        overlayFill.isHidden = !floating
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

    /// Thumbnails are fetched for the rows that are on screen, and when the queue is first read there is no "on
    /// screen" yet: the table has no geometry, its visible rectangle is empty, and the fetch asks for nothing at all.
    /// Only a scroll or a mode change asked again afterwards, which is why a queue sat there blank until it was
    /// touched. Layout is the first moment the question has a real answer, so it is asked again here — including for
    /// a queue whose rows all fit without scrolling, which never gets a scroll to ask on its behalf. Cheap to repeat:
    /// a row whose image is already in hand, or already requested, is skipped.
    override func viewDidLayout() {
        super.viewDidLayout()
        applyPendingScrollOffset()
        loadVisibleThumbnails()
        loadVisibleTitles()
    }

    // MARK: - Scroll position across launches

    /// Where the list was scrolled last session, waiting for the list to have rows and a height to scroll within.
    private var pendingScrollOffset: Double?

    /// How far down the list is scrolled, in points from the top. The table is flipped, so this is `origin.y`.
    var scrollOffset: CGFloat {
        scrollView.contentView.bounds.origin.y
    }

    /// Scrolls to where the list was last session, as soon as there is a list to scroll.
    func restoreScrollOffset(_ stored: Double?) {
        pendingScrollOffset = stored
        applyPendingScrollOffset()
    }

    /// Applied once, the first time the list has rows and a visible height — both needed to clamp it — and then
    /// forgotten, so a later layout can never yank the list back to where it was at launch.
    private func applyPendingScrollOffset() {
        guard let stored = pendingScrollOffset, tableView.numberOfRows > 0 else { return }
        let visibleHeight = Double(scrollView.contentView.bounds.height)
        guard visibleHeight > 0,
              let offset = SidebarRestore.scrollOffset(
                  stored: stored,
                  contentHeight: Double(tableView.bounds.height),
                  visibleHeight: visibleHeight
              )
        else { return }
        pendingScrollOffset = nil
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    @objc private func visibleRowsChanged() {
        loadVisibleThumbnails()
        loadVisibleTitles()
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
        loadVisibleTitles()
    }

    /// Marks the video playing now and brings its row into view.
    ///
    /// Only when the video actually changed. This is called on every queue change, and scrolling on each one would
    /// fight the reader: someone browsing a long list would be yanked back to the playing row every few seconds.
    /// The selection is left alone for the same reason — it belongs to whoever made it, not to playback.
    func setCurrentVideo(_ videoID: VideoID?) {
        let changed = videoID != currentVideoID
        currentVideoID = videoID
        reload()
        guard changed, let videoID,
              let index = rows.firstIndex(where: { $0.videoID == videoID.rawValue })
        else { return }
        // A video starting is a newer intent than where the list sat last session: a bookmarklet click that launched
        // the app should land on that video's row, not on yesterday's scroll position.
        pendingScrollOffset = nil
        tableView.scrollRowToVisible(index)
    }

    func setMode(_ newMode: QueueDisplayMode) {
        mode = newMode
        modeButton.selectItem(at: QueueDisplayMode.allCases.firstIndex(of: newMode) ?? 0)
        reload()
        onModeChange?(newMode)
    }

    @objc private func changeMode(_ sender: NSPopUpButton) {
        let modes = QueueDisplayMode.allCases
        setMode(modes[min(max(sender.indexOfSelectedItem, 0), modes.count - 1)])
    }

    // MARK: - Actions

    @objc private func playSelectedRow() {
        guard let videoID = targetVideoIDs().first else { return }
        onPlay?(videoID)
    }

    @objc private func removeSelectedRows() {
        change { store in
            for videoID in targetVideoIDs() {
                try store.remove(videoID)
            }
        }
    }

    @objc private func markSelectedWatched() {
        change { store in
            for videoID in targetVideoIDs() {
                try store.markWatched(videoID)
            }
        }
    }

    @objc private func markSelectedUnwatched() {
        change { store in
            for videoID in targetVideoIDs() {
                try store.markUnwatched(videoID)
            }
        }
    }

    @objc private func copySelectedLinks() {
        let links = targetVideoIDs().map { AddRequest.watchURL(for: $0).absoluteString }
        guard !links.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(links.joined(separator: "\n"), forType: .string)
    }

    /// Opens the video on YouTube in whatever browser the system prefers. Cue plays it without the browser, but the
    /// page is still where the description, the comments and the channel live.
    @objc private func openSelectedInBrowser() {
        for videoID in targetVideoIDs() {
            NSWorkspace.shared.open(AddRequest.watchURL(for: videoID))
        }
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

    /// What a context menu item acts on: the row that was right-clicked, unless it is part of the selection, in which
    /// case the whole selection.
    ///
    /// Reading the selection alone was wrong in both directions. With nothing selected it returned nothing, so every
    /// item did nothing at all and said nothing about it — which is how "Copy Link" appeared to be broken. With a
    /// different row selected it acted on that one instead of the row under the pointer, which is worse: the wrong
    /// video quietly removed or copied. `clickedRow` is -1 outside a menu, so the keyboard paths still mean the
    /// selection.
    private func targetVideoIDs() -> [VideoID] {
        let clicked = tableView.clickedRow
        guard rows.indices.contains(clicked) else { return selectedVideoIDs() }
        if tableView.selectedRowIndexes.contains(clicked) { return selectedVideoIDs() }
        return VideoID(rows[clicked].videoID).map { [$0] } ?? []
    }

    private func change(_ work: (QueueStore) throws -> Void) {
        do {
            try work(store)
        } catch {
            logger.error("Queue database error: \(String(describing: error), privacy: .private)")
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
        menu.addItem(NSMenuItem(title: "Open in Browser", action: #selector(openSelectedInBrowser), keyEquivalent: ""))
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

    // MARK: - Titles

    /// Names the videos on screen, the way thumbnails are fetched and for the same reason: a queue of hundreds must
    /// not ask about hundreds of videos because the sidebar was scrolled. A row whose title is already known, or
    /// already asked about, is skipped, so repeating this on every scroll and every layout costs nothing.
    ///
    /// Unlike thumbnails this runs in every display mode: a title is what the row says in all three.
    private func loadVisibleTitles() {
        let visible = tableView.rows(in: tableView.visibleRect)
        guard visible.length > 0 else { return }
        for row in visible.location..<(visible.location + visible.length) where rows.indices.contains(row) {
            let identifier = rows[row].videoID
            guard !rows[row].isTitleKnown, !requestedTitles.contains(identifier),
                  let videoID = VideoID(identifier) else { continue }
            requestedTitles.insert(identifier)
            pendingTitles.append(videoID)
        }
        fetchPendingTitles()
    }

    /// Drains `pendingTitles` one video at a time.
    ///
    /// Strictly sequential: one task, each answer awaited to the end before the next question is asked, so a sidebar
    /// scrolled through a long queue spreads its requests out instead of firing them all at once. A video that
    /// cannot be named is left as it is and the next one carries on: it was marked as asked about before the request
    /// went out, so a failure is never retried and one dead video cannot hold up the rest of the queue.
    private func fetchPendingTitles() {
        guard titleTask == nil, !pendingTitles.isEmpty else { return }
        titleTask = Task { [weak self, summaries] in
            while !Task.isCancelled, let videoID = self?.takeNextPendingTitle() {
                guard let summary = try? await summaries.summary(for: videoID) else { continue }
                self?.apply(summary)
            }
            self?.titleTask = nil
        }
    }

    private func takeNextPendingTitle() -> VideoID? {
        pendingTitles.isEmpty ? nil : pendingTitles.removeFirst()
    }

    /// Writes one answer through the store, so the title survives a relaunch, and redraws the row it belongs to.
    /// The store keeps whatever title is already there, so an answer that arrives for a video the owner has since
    /// played, or imported a title for, cannot overwrite it.
    private func apply(_ summary: VideoSummary) {
        do {
            // No duration: the oEmbed endpoint does not report one, and a video's duration is filled in by the
            // extractor when it is played.
            try store.updateMetadata(for: summary.videoID, title: summary.title, author: summary.author, duration: nil)
        } catch {
            // Never the id, the title or the URL, at any level: this is the owner's private queue.
            logger.error("Queue database error: \(String(describing: error), privacy: .private)")
            return
        }
        redrawRow(for: summary.videoID.rawValue)
    }

    /// Re-reads one video and redraws its row alone. Reloading the whole table on every answer would flicker through
    /// a long queue and fight the scroll the owner is in the middle of.
    private func redrawRow(for identifier: String) {
        guard let index = rows.firstIndex(where: { $0.videoID == identifier }),
              let videoID = VideoID(identifier),
              let video = (try? store.video(for: videoID)) ?? nil,
              let row = QueuePresentation.rows(for: [video], mode: mode, current: currentVideoID).first
        else { return }
        rows[index] = row
        tableView.reloadData(forRowIndexes: IndexSet(integer: index), columnIndexes: IndexSet(integer: 0))
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
        // A file is not dropped at a position: it is offered to the queue as a whole, so the table highlights itself
        // rather than a gap between two rows, and lands the same way wherever the pointer was.
        if DroppedFile.url(in: info) != nil {
            tableView.setDropRow(-1, dropOperation: .on)
            return .copy
        }
        guard dropOperation == .above else { return [] }
        return info.draggingSource as? NSTableView === tableView ? .move : .copy
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: any NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        if let file = DroppedFile.url(in: info) {
            onFileDrop?(file)
            return true
        }
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

/// The queue's ground while it floats over the picture: the window's own background colour at 85 %, opaque enough to
/// read a list against a moving image. Drawn rather than set as a layer colour, so the appearance is resolved again
/// every time it changes instead of being frozen at whatever was current when the view was built.
final class SidebarOverlayFill: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.withAlphaComponent(0.85).setFill()
        dirtyRect.fill()
    }
}
