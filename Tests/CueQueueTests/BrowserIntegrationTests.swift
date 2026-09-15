@testable import CueQueue
import Foundation
import Testing

@Suite struct BrowserIntegrationTests {
    @Test func theBookmarkletSendsThePageItRunsOnToCue() {
        #expect(BrowserIntegration.bookmarklet.hasPrefix("javascript:"))
        #expect(BrowserIntegration.bookmarklet.contains("cue://add?url="))
        // Without this the query of a watch URL would be swallowed into the outer link's own query.
        #expect(BrowserIntegration.bookmarklet.contains("encodeURIComponent(location.href)"))
    }

    @Test func thePageCarriesTheBookmarkletAsADraggableLink() {
        let page = BrowserIntegration.page()
        #expect(page.contains("href=\"\(BrowserIntegration.bookmarklet)\""))
        // The same text again in the field people copy from when dragging fails.
        #expect(page.contains("value=\"\(BrowserIntegration.bookmarklet)\""))
    }

    @Test func thePageFetchesNothingFromTheNetwork() {
        let page = BrowserIntegration.page()
        // The one thing this page must never do. A stylesheet, a font or a script from outside would make an
        // offline app phone somewhere just to explain itself, which is the rule this whole project is built on.
        #expect(!page.contains("http://"))
        #expect(!page.contains("https://"))
        #expect(!page.contains("src=\""))
        #expect(!page.contains("@import"))
    }

    @Test func thePageIsSelfContainedHTML() {
        let page = BrowserIntegration.page()
        #expect(page.hasPrefix("<!DOCTYPE html>"))
        #expect(page.contains("<html lang=\"en\">"))
        #expect(page.hasSuffix("</html>"))
        #expect(page.contains("charset=\"utf-8\""))
    }

    @Test func thePageTellsEachBrowserWhereItsBookmarksBarIs() {
        let page = BrowserIntegration.page()
        for browser in ["Chrome", "Firefox", "Safari"] {
            #expect(page.contains(browser))
        }
    }

    @Test func thePageHasANameThatSaysWhatItIs() {
        #expect(BrowserIntegration.pageFileName.hasSuffix(".html"))
        #expect(BrowserIntegration.pageFileName.contains("cue"))
    }

    @Test func copyingSaysWhatToDoNext() {
        #expect(BrowserIntegration.copiedMessage.contains("bookmark"))
    }
}
