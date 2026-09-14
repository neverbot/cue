import Foundation

/// What the About window says. Every string it shows is decided here, where it can be tested: `Sources/Cue` has no
/// automated coverage by design, so the window itself only lays these out.
public enum AboutPresentation {
    public static let appName = "Cue"

    /// One line under the name. Not a slogan: it says what the app is for someone who opened this window to find out.
    public static let summary = "A personal YouTube watch-later queue, played natively."

    /// Cue's own licence, said plainly. The full text ships in the bundle beside the third-party ones.
    public static let ownLicense = "Cue's own code is released under the MIT License."

    /// Where the licence texts live inside the app, and the name of the document listing what is bundled. Both the
    /// window and the packaging script depend on this layout; naming it once means they cannot drift apart silently.
    public static let licensesDirectoryName = "licenses"
    public static let thirdPartyDocumentName = "third-party-licenses.md"

    /// "Version 0.4.0 (build 1)", or as much of it as the bundle actually declares.
    ///
    /// A missing value is left out rather than written as "unknown": this window exists to be quoted back in a bug
    /// report, and a made-up version is worse than a short line. Running from `swift run` there is no Info.plist at
    /// all, which is the case that returns the bare fallback.
    public static func versionLine(shortVersion: String?, build: String?) -> String {
        let version = shortVersion?.trimmingCharacters(in: .whitespaces)
        let buildNumber = build?.trimmingCharacters(in: .whitespaces)
        switch (version?.isEmpty == false ? version : nil, buildNumber?.isEmpty == false ? buildNumber : nil) {
        case let (version?, build?) where version != build:
            return "Version \(version) (build \(build))"
        case let (version?, _):
            return "Version \(version)"
        case (nil, let build?):
            return "Build \(build)"
        case (nil, nil):
            return "Built from source"
        }
    }

    /// The copyright line the bundle declares, or the project's own when there is none to read.
    public static func copyrightLine(_ declared: String?) -> String {
        let trimmed = declared?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "© 2026 Iván Alonso" : trimmed
    }

    /// Said when the bundled licence document cannot be read — running from `swift run`, or from a bundle someone
    /// assembled by hand. It names every component that carries an obligation rather than apologising: an LGPL
    /// notice that only appears when a file happens to be present is not a notice.
    public static let fallbackLicenses = """
        Cue bundles third-party code. The full licence texts ship inside Cue.app, in \
        Contents/Resources/\(licensesDirectoryName)/.

        libmpv and FFmpeg — GNU Lesser General Public License (LGPL 2.1+ and 3+), built without GPL components and \
        linked as a replaceable shared library.

        GRDB.swift — MIT License. Links the SQLite that ships with macOS; SQLite itself is public domain.

        yt-dlp-ejs — The Unlicense (public domain dedication), bundling meriyah (ISC) and astring (MIT).
        """

    /// The text to show for the bundled components: the packaged document when it could be read, and the fallback
    /// when it could not. Emptiness is treated as absence, since an empty file says nothing either.
    public static func licensesText(document: String?) -> String {
        let markdown = document?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return markdown.isEmpty ? fallbackLicenses : plainText(fromMarkdown: markdown)
    }

    /// Turns the packaged Markdown into something a plain text view can show without its punctuation showing through.
    ///
    /// Deliberately a light touch rather than a Markdown renderer: this document is ours, its shape is known, and the
    /// point is only that a reader does not see `##`, `**` and backticks. Anything unrecognised is left exactly as it
    /// was, so a line this does not understand still reaches the reader intact — including the URLs, which are the
    /// part an auditor actually follows.
    public static func plainText(fromMarkdown markdown: String) -> String {
        markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var text = String(line)
                if let hashes = text.range(of: "^#{1,6} ", options: .regularExpression) {
                    text.removeSubrange(hashes)
                }
                // A list marker becomes a real bullet; an indented one keeps its indent, so nesting survives.
                if let dash = text.range(of: "^(\\s*)- ", options: .regularExpression) {
                    let indent = text[dash].dropLast(2)
                    text.replaceSubrange(dash, with: indent + "• ")
                }
                return text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            }
            .joined(separator: "\n")
    }
}
