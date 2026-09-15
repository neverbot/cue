import AppKit
import CueQueue
import os

/// Writes the bookmarklet page to a file and opens it in the default browser.
///
/// A file rather than a served page: Cue runs no server and opens no port. The browser loads it from disk, and
/// what the reader sees is a page that fetches nothing — which is also the only honest way to claim, on the page
/// itself, that nothing is sent anywhere.
enum BrowserIntegrationPage {
    private static let logger = Logger(subsystem: "com.neverbot.cue", category: "browser")

    /// Written into the temporary directory, not Application Support: it is a leaflet, not data. The system clears
    /// it eventually, and Cue writes it again whenever it is asked.
    private static var fileURL: URL {
        FileManager.default.temporaryDirectory
            .appending(path: "Cue", directoryHint: .isDirectory)
            .appending(path: BrowserIntegration.pageFileName, directoryHint: .notDirectory)
    }

    /// Writes the page and hands it to whichever browser the user has set as their default.
    static func open(relativeTo window: NSWindow?) {
        do {
            let url = fileURL
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try BrowserIntegration.page().write(to: url, atomically: true, encoding: .utf8)
            // Rewritten every time rather than cached: the page is small, and a stale copy left by an older
            // version would quietly teach the wrong thing.
            NSWorkspace.shared.open(url)
        } catch {
            logger.error("Could not write the browser integration page: \(String(describing: error), privacy: .private)")
            let alert = NSAlert()
            alert.messageText = "Cue could not open the bookmarklet page."
            alert.informativeText = """
                The page is written to a temporary file before it is opened, and that failed. \
                You can still add the bookmarklet by hand: copy it from Settings ▸ Browser Integration.
                """
            alert.addButton(withTitle: "OK")
            if let window {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
        }
    }

    /// Puts the bookmarklet on the clipboard, for anyone who would rather paste it than drag it.
    static func copyBookmarklet() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(BrowserIntegration.bookmarklet, forType: .string)
    }
}
