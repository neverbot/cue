import AppKit
import CueQueue

/// Cue ▸ About Cue: the app's icon, what it is, which version this is, who wrote it, and what it bundles.
///
/// Not `orderFrontStandardAboutPanel`. The standard panel shows a credits blob in a fixed, unscrollable box, and what
/// has to be shown here is a licence document of a few hundred lines — LGPL components carry an obligation to state
/// them, so this is the one window in the app whose content is not ours to summarise away.
///
/// The licence text is read from the bundle rather than compiled in, so the document that ships and the document on
/// screen cannot disagree: they are the same file. `AboutPresentation` decides every string, including what to say
/// when that file cannot be read.
final class AboutWindowController: NSWindowController, NSWindowDelegate {
    /// Escape closes this window. A local monitor rather than `cancelOperation(_:)` for the same reason the player
    /// window monitors its own keys: the licence text view is a first responder that handles keys itself, and a
    /// responder-chain override only fires if every responder below it declines to act. Watching the event is not an
    /// assumption about who holds focus.
    private var escapeMonitor: Any?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
            // Resizable, unlike Settings: this one holds a long document, and the reader may want it taller.
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Cue"
        window.isRestorable = false
        window.minSize = NSSize(width: 420, height: 380)
        super.init(window: window)
        window.contentView = makeContent()
        window.center()
        window.delegate = self
    }

    /// The monitor lives exactly as long as the window is on screen. It is installed here rather than in `init`
    /// because this controller is kept between openings, and taken down again in `windowWillClose`: a monitor left
    /// running while the window is closed would be watching every key press in the app to answer none of them.
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        guard escapeMonitor == nil else { return }
        // Scoped to this window: Escape anywhere else in Cue — the player, settings, a sheet — is none of its
        // business, and a monitor that closed this window from another one would be a bug with no symptom until
        // someone pressed Escape while watching a video.
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window, event.keyCode == 53 else { return event }
            self.close()
            return nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let escapeMonitor else { return }
        NSEvent.removeMonitor(escapeMonitor)
        self.escapeMonitor = nil
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func makeContent() -> NSView {
        // The app's own icon, from the running application rather than loaded by name: it is already the one the Dock
        // and the Finder show, so this cannot end up displaying a stale copy of an icon that was replaced.
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 96).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 96).isActive = true

        let name = NSTextField(labelWithString: AboutPresentation.appName)
        name.font = .systemFont(ofSize: 26, weight: .semibold)

        let info = Bundle.main.infoDictionary
        let version = NSTextField(labelWithString: AboutPresentation.versionLine(
            shortVersion: info?["CFBundleShortVersionString"] as? String,
            build: info?["CFBundleVersion"] as? String
        ))
        version.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        version.textColor = .secondaryLabelColor
        // Selectable so a version can be copied into a bug report instead of retyped from a screenshot.
        version.isSelectable = true

        let summary = NSTextField(labelWithString: AboutPresentation.summary)
        summary.font = .systemFont(ofSize: NSFont.systemFontSize)
        summary.textColor = .secondaryLabelColor

        let copyright = NSTextField(labelWithString: AboutPresentation.copyrightLine(
            info?["NSHumanReadableCopyright"] as? String
        ))
        copyright.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        copyright.isSelectable = true

        let license = NSTextField(labelWithString: AboutPresentation.ownLicense)
        license.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        license.textColor = .secondaryLabelColor

        let header = NSStackView(views: [name, version, summary])
        header.orientation = .vertical
        header.alignment = .centerX
        header.spacing = 2
        header.setCustomSpacing(8, after: version)

        let heading = NSTextField(labelWithString: "Included components and their licenses")
        heading.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

        let stack = NSStackView(views: [icon, header, copyright, license, heading, licensesView()])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(14, after: header)
        stack.setCustomSpacing(18, after: license)
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    /// The bundled licence document, scrollable and selectable but not editable.
    private func licensesView() -> NSView {
        let textView = NSTextView()
        textView.isEditable = false
        // Selectable, because a licence nobody can copy out is a licence that is awkward to comply with.
        textView.isSelectable = true
        textView.drawsBackground = false
        // Monospaced, and not as a style choice: the document contains tables, and `AboutPresentation` lines their
        // columns up by padding with spaces. In a proportional font that padding does not line anything up.
        textView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.string = AboutPresentation.licensesText(document: bundledLicenseDocument())
        textView.textColor = .labelColor
        // Wrap rather than scroll sideways: the document is prose and URLs, and a horizontal scroller on prose is a
        // way of hiding half of it.
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        return scrollView
    }

    /// Reads the licence document that `scripts/make-app.sh` copies into the bundle. Nil when there is no bundle to
    /// read from — running the executable straight out of `.build`, where `Resources/` does not exist.
    private func bundledLicenseDocument() -> String? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let url = resources
            .appendingPathComponent(AboutPresentation.licensesDirectoryName)
            .appendingPathComponent(AboutPresentation.thirdPartyDocumentName)
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
