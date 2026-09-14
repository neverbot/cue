import Testing

@testable import CueQueue

@Suite("About window text")
struct AboutPresentationTests {
    @Test("Names both the version and the build when the bundle declares them")
    func versionAndBuild() {
        #expect(AboutPresentation.versionLine(shortVersion: "0.4.0", build: "1") == "Version 0.4.0 (build 1)")
    }

    @Test("Leaves out a build number that only repeats the version")
    func buildRepeatingVersion() {
        #expect(AboutPresentation.versionLine(shortVersion: "0.4.0", build: "0.4.0") == "Version 0.4.0")
    }

    @Test("Says what it knows when a value is missing or blank, and never invents one")
    func missingValues() {
        #expect(AboutPresentation.versionLine(shortVersion: "0.4.0", build: nil) == "Version 0.4.0")
        #expect(AboutPresentation.versionLine(shortVersion: "  ", build: "7") == "Build 7")
        #expect(AboutPresentation.versionLine(shortVersion: nil, build: nil) == "Built from source")
    }

    @Test("Prefers the bundle's own copyright line, and falls back to the project's")
    func copyright() {
        #expect(AboutPresentation.copyrightLine("© 2026 Someone Else") == "© 2026 Someone Else")
        #expect(AboutPresentation.copyrightLine(nil) == "© 2026 Iván Alonso")
        #expect(AboutPresentation.copyrightLine("   ") == "© 2026 Iván Alonso")
    }

    @Test("Falls back to the built-in notice when the packaged document is missing or empty")
    func fallbackWhenDocumentAbsent() {
        #expect(AboutPresentation.licensesText(document: nil) == AboutPresentation.fallbackLicenses)
        #expect(AboutPresentation.licensesText(document: "\n  \n") == AboutPresentation.fallbackLicenses)
    }

    @Test("The fallback still names every component that carries an obligation")
    func fallbackNamesObligations() {
        let text = AboutPresentation.fallbackLicenses
        #expect(text.contains("Lesser General Public License"))
        #expect(text.contains("libmpv"))
        #expect(text.contains("FFmpeg"))
        #expect(text.contains("GRDB"))
        #expect(text.contains("Unlicense"))
    }

    @Test("Strips heading marks, emphasis and backticks from the packaged document")
    func stripsMarkdownPunctuation() {
        let markdown = """
            # Third-party licenses

            ## libmpv and FFmpeg (LGPL build)

            Cue links `libmpv.2.dylib` as a **shared** library.
            """
        let plain = AboutPresentation.plainText(fromMarkdown: markdown)
        #expect(!plain.contains("#"))
        #expect(!plain.contains("**"))
        #expect(!plain.contains("`"))
        #expect(plain.contains("Third-party licenses"))
        #expect(plain.contains("libmpv and FFmpeg (LGPL build)"))
        #expect(plain.contains("Cue links libmpv.2.dylib as a shared library."))
    }

    @Test("Turns list markers into bullets and keeps their indentation")
    func bullets() {
        let plain = AboutPresentation.plainText(fromMarkdown: "- meriyah 6.1.4\n  - astring 1.9.0")
        #expect(plain == "• meriyah 6.1.4\n  • astring 1.9.0")
    }

    @Test("Leaves URLs untouched, since those are what an auditor follows")
    func keepsURLs() {
        let plain = AboutPresentation.plainText(fromMarkdown: "- **mpv** — https://github.com/mpv-player/mpv")
        #expect(plain == "• mpv — https://github.com/mpv-player/mpv")
    }

    @Test("Lays a table out in columns instead of leaving its pipes on screen")
    func table() {
        let markdown = """
            | Component | License |
            |---|---|
            | libass 0.17.5 | ISC |
            | FreeType 2.14.3 | FreeType License (FTL) |
            """
        let plain = AboutPresentation.plainText(fromMarkdown: markdown)
        // The first column is as wide as "FreeType 2.14.3", its widest cell, plus two spaces of gutter.
        #expect(plain == """
            Component        License
            ------------------------
            libass 0.17.5    ISC
            FreeType 2.14.3  FreeType License (FTL)
            """)
    }

    @Test("Leaves the last column ragged, so one long cell cannot widen the whole block")
    func tableLastColumnIsNotPadded() {
        let markdown = """
            | Component | License |
            |---|---|
            | LuaJIT 2.1 | MIT |
            | uchardet 0.0.8 | LGPL-2.1-or-later (chosen from three) |
            """
        let lines = AboutPresentation.plainText(fromMarkdown: markdown).split(separator: "\n").map(String.init)
        // No line is padded out to the width of the longest one, and none ends in stray spaces.
        #expect(lines.allSatisfy { $0 == $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) })
        // Padded to "uchardet 0.0.8", the widest cell in the column, and no further.
        #expect(lines.contains("LuaJIT 2.1      MIT"))
    }

    @Test("A table of one row needs no rule under it")
    func singleRowTable() {
        #expect(AboutPresentation.plainText(fromMarkdown: "| Component | License |") == "Component  License")
    }

    @Test("Text on either side of a table is untouched")
    func textAroundATable() {
        let markdown = """
            Cue links these:

            | Component | License |
            |---|---|
            | dav1d 1.5.3 | BSD-2-Clause |

            The full texts ship in the bundle.
            """
        let plain = AboutPresentation.plainText(fromMarkdown: markdown)
        #expect(plain.hasPrefix("Cue links these:\n\n"))
        #expect(plain.hasSuffix("\n\nThe full texts ship in the bundle."))
        #expect(!plain.contains("|"))
    }

    @Test("Keeps blank lines, so the paragraphs of the document survive")
    func keepsBlankLines() {
        let plain = AboutPresentation.plainText(fromMarkdown: "One\n\nTwo")
        #expect(plain == "One\n\nTwo")
    }
}
