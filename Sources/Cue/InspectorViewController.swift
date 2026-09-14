import AppKit
import CueQueue

/// The window's trailing inspector: the chapters list and the subtitles controls, one at a time, chosen with a
/// segmented control at the top. Both pages exist from the start and only their visibility changes, so switching
/// tabs never rebuilds a list or loses a scroll position.
///
/// It replaces the two floating utility panels the two lists used to live in: a panel takes key focus away from the
/// player, drifts behind the window and is easy to lose, and this sits in the same window as the queue's leading
/// sidebar, which is the shape the rest of the app already has.
final class InspectorViewController: NSViewController {
    /// The same width the queue sidebar opens at, so both sides of the window read as one family.
    static let width: CGFloat = 280

    let chapters = ChaptersViewController()
    let subtitles = SubtitlesViewController()

    private(set) var tab: InspectorTab
    private let tabs = NSSegmentedControl(
        labels: InspectorTab.allCases.map(\.title),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )

    /// Called when the user picks a tab here, so the window can remember which one was last in front.
    var onTabChange: ((InspectorTab) -> Void)?

    /// The tab is handed in rather than set afterwards, so the restored one is in place before the view is built and
    /// the control is never briefly showing a page that is not the one on screen.
    init(tab: InspectorTab = .chapters) {
        self.tab = tab
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: Self.width, height: 400))
        // The same ground the queue sidebar is drawn on, for the same reason: a column beside the video is a surface
        // of its own, not chrome over the picture, so it takes the platform's sidebar material and follows the
        // appearance. Nothing painted here before and the window's black showed through the whole inspector.
        container.material = .sidebar
        container.blendingMode = .behindWindow
        container.state = .followsWindowActiveState
        tabs.target = self
        tabs.action = #selector(tabClicked)
        tabs.segmentDistribution = .fillEqually
        tabs.selectedSegment = InspectorTab.allCases.firstIndex(of: tab) ?? 0
        tabs.setAccessibilityLabel("Inspector page")
        tabs.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tabs)

        addChild(chapters)
        addChild(subtitles)
        var constraints = [
            // The safe area, never a hardcoded inset: this column runs under a title bar the window draws over its
            // content, and only the window knows how tall that is.
            tabs.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 8),
            tabs.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            tabs.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
        ]
        for page in [chapters.view, subtitles.view] {
            page.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(page)
            constraints += [
                page.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 8),
                page.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                page.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        view = container
        showSelectedPage()
    }

    /// Brings a tab to the front from outside — a menu item, a shortcut or a button in the controls bar. The callback
    /// is not fired: whatever called this already knows.
    func setTab(_ newTab: InspectorTab) {
        tab = newTab
        tabs.selectedSegment = InspectorTab.allCases.firstIndex(of: newTab) ?? 0
        showSelectedPage()
    }

    @objc private func tabClicked() {
        guard let picked = InspectorTab.allCases[safe: tabs.selectedSegment] else { return }
        tab = picked
        showSelectedPage()
        onTabChange?(picked)
    }

    private func showSelectedPage() {
        guard isViewLoaded else { return }
        chapters.view.isHidden = tab != .chapters
        subtitles.view.isHidden = tab != .subtitles
    }
}

private extension Array {
    /// The segmented control reports -1 when nothing is selected, and an index this build has no tab for would be a
    /// control and an enum that disagree; either way there is nothing to switch to.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
