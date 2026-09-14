import AppKit
import CueCore
import CuePlayer

/// Picks a caption track, styles it, delays it and exports it. The panel holds no logic: `SubtitleSession` decides
/// what mpv is told, and `SubtitleWriter` decides what an export contains.
final class SubtitlesPanelController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    /// Row 0 is "Off"; the rest are tracks.
    var onSelect: ((CaptionTrack?) -> Void)?
    var onStyleChange: ((SubtitleStyle) -> Void)?
    var onDelayChange: ((Double) -> Void)?
    var onExport: ((ExportFormat) -> Void)?

    private let tableView = NSTableView()
    private let sizeButton = NSPopUpButton()
    private let colourButton = NSPopUpButton()
    private let boxSwitch = NSButton(checkboxWithTitle: "Background box", target: nil, action: nil)
    private let delaySlider = NSSlider(value: 0, minValue: -5, maxValue: 5, target: nil, action: nil)
    private let delayLabel = NSTextField(labelWithString: "0.0 s")
    private let statusLabel = NSTextField(labelWithString: "")

    private var tracks: [CaptionTrack] = []
    private var style = SubtitleStyle()

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 460),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Subtitles"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        super.init(window: panel)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("track"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .inset
        tableView.rowHeight = 24
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        sizeButton.addItems(withTitles: SubtitleStyle.Size.allCases.map(\.title))
        sizeButton.selectItem(at: SubtitleStyle.Size.allCases.firstIndex(of: style.size) ?? 1)
        sizeButton.target = self
        sizeButton.action = #selector(styleChanged)
        colourButton.addItems(withTitles: SubtitleStyle.Colour.allCases.map(\.title))
        colourButton.target = self
        colourButton.action = #selector(styleChanged)
        boxSwitch.target = self
        boxSwitch.action = #selector(styleChanged)

        delaySlider.target = self
        delaySlider.action = #selector(delayChanged)
        delaySlider.isContinuous = true
        delayLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        let exportSRT = NSButton(title: "Export SRT…", target: self, action: #selector(exportSRT))
        let exportVTT = NSButton(title: "Export VTT…", target: self, action: #selector(exportVTT))
        let exports = NSStackView(views: [exportSRT, exportVTT])
        exports.orientation = .horizontal
        exports.distribution = .fillEqually

        let delayRow = NSStackView(views: [NSTextField(labelWithString: "Delay"), delaySlider, delayLabel])
        delayRow.orientation = .horizontal
        let styleRow = NSStackView(views: [NSTextField(labelWithString: "Size"), sizeButton, NSTextField(labelWithString: "Colour"), colourButton])
        styleRow.orientation = .horizontal

        let column0 = NSStackView(views: [scrollView, styleRow, boxSwitch, delayRow, exports, statusLabel])
        column0.orientation = .vertical
        column0.spacing = 8
        column0.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        column0.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(column0)
        if let content = panel.contentView {
            NSLayoutConstraint.activate([
                column0.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                column0.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                column0.topAnchor.constraint(equalTo: content.topAnchor),
                column0.bottomAnchor.constraint(equalTo: content.bottomAnchor),
                scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
            ])
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setTracks(_ tracks: [CaptionTrack], selected: CaptionTrack?, style: SubtitleStyle, delay: Double) {
        self.tracks = tracks
        self.style = style
        tableView.reloadData()
        let row = selected.flatMap { track in tracks.firstIndex { $0.id == track.id }.map { $0 + 1 } } ?? 0
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        sizeButton.selectItem(at: SubtitleStyle.Size.allCases.firstIndex(of: style.size) ?? 1)
        colourButton.selectItem(at: SubtitleStyle.Colour.allCases.firstIndex(of: style.colour) ?? 0)
        boxSwitch.state = style.hasBackgroundBox ? .on : .off
        delaySlider.doubleValue = delay
        delayLabel.stringValue = String(format: "%.1f s", delay)
    }

    func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    @objc private func rowClicked() {
        let row = tableView.selectedRow
        onSelect?(row <= 0 ? nil : tracks[row - 1])
    }

    @objc private func styleChanged() {
        style.size = SubtitleStyle.Size.allCases[max(0, sizeButton.indexOfSelectedItem)]
        style.colour = SubtitleStyle.Colour.allCases[max(0, colourButton.indexOfSelectedItem)]
        style.hasBackgroundBox = boxSwitch.state == .on
        onStyleChange?(style)
    }

    @objc private func delayChanged() {
        let rounded = (delaySlider.doubleValue * 10).rounded() / 10
        delayLabel.stringValue = String(format: "%.1f s", rounded)
        onDelayChange?(rounded)
    }

    @objc private func exportSRT() { onExport?(.srt) }
    @objc private func exportVTT() { onExport?(.vtt) }

    func numberOfRows(in tableView: NSTableView) -> Int { tracks.count + 1 }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        row == 0 ? "Off" : tracks[row - 1].menuTitle
    }
}
