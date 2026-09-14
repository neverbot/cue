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

    @Test("Keeps blank lines, so the paragraphs of the document survive")
    func keepsBlankLines() {
        let plain = AboutPresentation.plainText(fromMarkdown: "One\n\nTwo")
        #expect(plain == "One\n\nTwo")
    }
}
