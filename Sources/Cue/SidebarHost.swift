import AppKit
import CueQueue

/// Holds the queue sidebar in one of two places and moves it between them: inside the split view, where it pushes
/// the video aside, or floating over the video. The sidebar view controller is the same object either way; only its
/// parent changes.
@MainActor
final class SidebarHost {
    let sidebar: QueueSidebarViewController

    private(set) var layout: SidebarLayout
    private(set) var isVisible: Bool

    /// The split view item the sidebar occupies in `push` layout.
    private let splitItem: NSSplitViewItem
    /// The view it floats in, over the video, in `overlay` layout.
    private let overlayContainer: NSView
    private let parent: NSViewController
    private var overlayConstraints: [NSLayoutConstraint] = []

    init(
        sidebar: QueueSidebarViewController,
        splitItem: NSSplitViewItem,
        overlayContainer: NSView,
        parent: NSViewController,
        layout: SidebarLayout = .push,
        isVisible: Bool = true
    ) {
        self.sidebar = sidebar
        self.splitItem = splitItem
        self.overlayContainer = overlayContainer
        self.parent = parent
        self.layout = layout
        self.isVisible = isVisible
        apply()
    }

    func toggleVisible() {
        setVisible(!isVisible)
    }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        apply()
    }

    func setLayout(_ newLayout: SidebarLayout) {
        guard newLayout != layout else { return }
        layout = newLayout
        apply()
    }

    /// Collapsing is deliberately not animated. The window controller measures the picture immediately after this
    /// returns so it can give the window back exactly the width the column took, and an animation in flight reports
    /// an intermediate width — which would leave the correction wrong and the video letterboxed, the very defect
    /// this measuring exists to remove. The inspector gave up its animation for the same reason.
    private func apply() {
        switch (layout, isVisible) {
        case (.push, let visible):
            detachFromOverlay()
            attachToSplitItem()
            splitItem.isCollapsed = !visible
        case (.overlay, true):
            splitItem.isCollapsed = true
            attachToOverlay()
        case (.overlay, false):
            splitItem.isCollapsed = true
            detachFromOverlay()
        }
    }

    private func attachToSplitItem() {
        guard sidebar.parent !== splitItem.viewController else { return }
        let container = splitItem.viewController
        // Beside the video the queue is a surface of its own, so it takes the platform's sidebar material back.
        sidebar.setFloatingOverVideo(false)
        sidebar.removeFromParent()
        sidebar.view.removeFromSuperview()
        container.addChild(sidebar)
        sidebar.view.translatesAutoresizingMaskIntoConstraints = false
        container.view.addSubview(sidebar.view)
        NSLayoutConstraint.activate([
            sidebar.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            sidebar.view.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
            sidebar.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            sidebar.view.bottomAnchor.constraint(equalTo: container.view.bottomAnchor),
        ])
    }

    private func attachToOverlay() {
        guard sidebar.view.superview !== overlayContainer else { return }
        sidebar.removeFromParent()
        sidebar.view.removeFromSuperview()
        parent.addChild(sidebar)
        sidebar.view.translatesAutoresizingMaskIntoConstraints = false
        // Over the picture the queue paints its own ground: the sidebar material blends with what is behind the
        // window, which over a video is the desktop, not the video.
        sidebar.setFloatingOverVideo(true)
        overlayContainer.addSubview(sidebar.view)
        overlayConstraints = [
            sidebar.view.leadingAnchor.constraint(equalTo: overlayContainer.leadingAnchor),
            sidebar.view.topAnchor.constraint(equalTo: overlayContainer.topAnchor),
            sidebar.view.bottomAnchor.constraint(equalTo: overlayContainer.bottomAnchor),
            sidebar.view.widthAnchor.constraint(equalToConstant: QueueSidebarViewController.width),
        ]
        NSLayoutConstraint.activate(overlayConstraints)
    }

    private func detachFromOverlay() {
        guard sidebar.view.superview === overlayContainer else { return }
        NSLayoutConstraint.deactivate(overlayConstraints)
        overlayConstraints = []
        sidebar.removeFromParent()
        sidebar.view.removeFromSuperview()
    }
}
