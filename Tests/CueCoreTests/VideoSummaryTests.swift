@testable import CueCore
import Foundation
import Testing

@Suite struct VideoSummaryTests {
    private let videoID = VideoID("dQw4w9WgXcQ")!

    @Test func asksTheOEmbedEndpointForOneVideo() {
        let url = OEmbedSummaries.url(for: videoID)
        let components = try! #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.host == "www.youtube.com")
        #expect(components.path == "/oembed")
        #expect(components.queryItems?.first { $0.name == "format" }?.value == "json")
        #expect(components.queryItems?.first { $0.name == "url" }?.value == WatchPage.url(for: videoID).absoluteString)
    }

    @Test func readsTheTitleAndAuthor() async throws {
        let http = StubHTTPClient()
        http.on(path: "/oembed", body: Data(#"{"title":"Never Gonna Give You Up","author_name":"Rick Astley"}"#.utf8))

        let summary = try await OEmbedSummaries(http: http).summary(for: videoID)

        #expect(summary.videoID == videoID)
        #expect(summary.title == "Never Gonna Give You Up")
        #expect(summary.author == "Rick Astley")
    }

    /// A video with no author named is still a video with a title: the row can use one without the other.
    @Test func acceptsAResponseWithoutAnAuthor() async throws {
        let http = StubHTTPClient()
        http.on(path: "/oembed", body: Data(#"{"title":"Me at the zoo"}"#.utf8))

        #expect(try await OEmbedSummaries(http: http).summary(for: videoID).author == nil)
    }

    /// A deleted or private video answers with a status, not a title.
    @Test func reportsAFailedRequest() async throws {
        let http = StubHTTPClient()
        http.on(path: "/oembed", status: 404, body: Data())

        await #expect(throws: VideoSummaryError.httpStatus(404)) {
            try await OEmbedSummaries(http: http).summary(for: videoID)
        }
    }

    @Test func rejectsAResponseItCannotRead() async throws {
        let http = StubHTTPClient()
        http.on(path: "/oembed", body: Data("not json".utf8))

        await #expect(throws: VideoSummaryError.unexpectedResponse) {
            try await OEmbedSummaries(http: http).summary(for: videoID)
        }
    }

    /// A blank title would replace an honest "not known yet" with an empty row, which says less than the id does.
    @Test func rejectsABlankTitle() async throws {
        let http = StubHTTPClient()
        http.on(path: "/oembed", body: Data(#"{"title":"   ","author_name":"Someone"}"#.utf8))

        await #expect(throws: VideoSummaryError.emptyTitle) {
            try await OEmbedSummaries(http: http).summary(for: videoID)
        }
    }
}
