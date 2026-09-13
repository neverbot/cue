import Foundation
import Testing
@testable import CueCore

@Suite struct WatchPageInitialDataTests {
    @Test func extractsTheObjectAfterTheAssignment() throws {
        let html = #"<script>var ytInitialData = {"a":1};</script>"#
        let data = try #require(WatchPage.initialData(in: html))
        #expect(String(decoding: data, as: UTF8.self) == #"{"a":1}"#)
    }

    @Test func stopsAtTheMatchingBrace() throws {
        let html = #"<script>var ytInitialData = {"a":{"b":2}};</script><script>var other = {"c":3};</script>"#
        let data = try #require(WatchPage.initialData(in: html))
        #expect(String(decoding: data, as: UTF8.self) == #"{"a":{"b":2}}"#)
    }

    @Test func ignoresBracesInsideStrings() throws {
        let html = #"<script>var ytInitialData = {"a":"}}}"};</script>"#
        let data = try #require(WatchPage.initialData(in: html))
        #expect(String(decoding: data, as: UTF8.self) == #"{"a":"}}}"}"#)
    }

    @Test func ignoresEscapedQuotes() throws {
        let html = #"<script>var ytInitialData = {"a":"say \"}\" twice"};</script>"#
        let data = try #require(WatchPage.initialData(in: html))
        #expect(String(decoding: data, as: UTF8.self) == #"{"a":"say \"}\" twice"}"#)
    }

    @Test func hasNoDataWhenTheAssignmentIsMissing() throws {
        #expect(WatchPage.initialData(in: try Fixture.string("watch-page-snippet.html")) == nil)
    }
}
