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
        var output: [String] = []
        var table: [[String]] = []

        func flushTable() {
            guard !table.isEmpty else { return }
            output += layOutTable(table)
            table = []
        }

        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if let cells = tableCells(in: line) {
                // A row of dashes is the separator under a header: it says nothing once the pipes are gone.
                if !cells.isEmpty { table.append(cells) }
                continue
            }
            flushTable()
            output.append(strippingInlineMarks(line))
        }
        flushTable()
        return output.joined(separator: "\n")
    }

    /// The cells of a Markdown table row, or nil when the line is not one. An empty array means a row that carries no
    /// content of its own — the `|---|---|` separator — which the caller drops.
    private static func tableCells(in line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") else { return nil }
        var cells = trimmed.split(separator: "|", omittingEmptySubsequences: false).map {
            strippingInlineMarks(String($0)).trimmingCharacters(in: .whitespaces)
        }
        // The leading and trailing pipes produce an empty cell at each end that was never a column.
        if cells.first?.isEmpty == true { cells.removeFirst() }
        if cells.last?.isEmpty == true { cells.removeLast() }
        let isSeparator = !cells.isEmpty && cells.allSatisfy {
            $0.range(of: "^:?-{2,}:?$", options: .regularExpression) != nil
        }
        return isSeparator ? [] : cells
    }

    /// Lays a table out in columns, since there is no Markdown renderer behind this text and the pipes would otherwise
    /// reach the reader as punctuation.
    ///
    /// Every column but the last is padded to its widest cell; the last is left ragged on purpose. Padding the last
    /// one would set the block's width by its longest line — here a licence that names three alternatives — and a
    /// table wider than the window is one that wraps, which destroys the very alignment the padding was for. This only
    /// lines up in a monospaced font, which is what the About window uses for exactly this reason.
    private static func layOutTable(_ rows: [[String]]) -> [String] {
        let columnCount = rows.map(\.count).max() ?? 0
        guard columnCount > 0 else { return [] }
        let widths = (0..<columnCount).map { column in
            rows.map { $0.indices.contains(column) ? $0[column].count : 0 }.max() ?? 0
        }

        var lines = rows.map { row in
            (0..<columnCount)
                .map { column -> String in
                    let cell = row.indices.contains(column) ? row[column] : ""
                    guard column < columnCount - 1 else { return cell }
                    return cell + String(repeating: " ", count: max(0, widths[column] - cell.count))
                }
                .joined(separator: "  ")
                // A short row would otherwise end in the padding of the columns it does not reach.
                .replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        }
        // A rule under the header, as wide as the header itself rather than as wide as the widest row: it separates
        // without drawing a line across a block whose right edge is deliberately ragged.
        if let header = lines.first, rows.count > 1 {
            lines.insert(String(repeating: "-", count: header.count), at: 1)
        }
        return lines
    }

    /// Heading marks, list markers, emphasis and backticks — everything that is punctuation in Markdown and noise in
    /// plain text. Anything unrecognised is left exactly as it was, URLs included.
    private static func strippingInlineMarks(_ line: String) -> String {
        var text = line
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
}
