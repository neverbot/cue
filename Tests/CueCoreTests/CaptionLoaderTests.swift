import Foundation
import Testing
@testable import CueCore

@Suite struct CaptionLoaderTests {
    let track = CaptionTrack(
        languageCode: "en",
        displayName: "English",
        isAutomatic: false,
        baseURL: URL(string: "https://www.youtube.com/api/timedtext?v=dQw4w9WgXcQ&lang=en")!
    )

    @Test func asksForJson3AndReturnsCues() async throws {
        let http = StubHTTPClient()
        http.on(path: "/api/timedtext", body: try Fixture.data("timedtext-json3.json"))

        let cues = try await CaptionLoader(http: http).cues(for: track, userAgent: "test-agent")

        #expect(cues.count == 4)
        #expect(http.recorded.first?.url.query?.contains("fmt=json3") == true)
    }

    /// Timed text is served under the same rules as the streams: the request must look like the one that resolved them.
    @Test func sendsTheUserAgent() async throws {
        let http = StubHTTPClient()
        http.on(path: "/api/timedtext", body: try Fixture.data("timedtext-json3.json"))

        _ = try await CaptionLoader(http: http).cues(for: track, userAgent: "test-agent")

        #expect(http.recorded.first?.headers["User-Agent"] == "test-agent")
    }

    @Test func reportsAnHTTPFailure() async throws {
        let http = StubHTTPClient()
        http.on(path: "/api/timedtext", status: 404, body: Data())

        await #expect(throws: ExtractionError.self) {
            try await CaptionLoader(http: http).cues(for: track, userAgent: "test-agent")
        }
    }

    /// A caption URL taken from the wrong place answers 200 with nothing in it. That is a failure, not a track
    /// without captions.
    @Test func reportsAnEmptyBody() async throws {
        let http = StubHTTPClient()
        http.on(path: "/api/timedtext", body: Data())

        await #expect(throws: ExtractionError.unexpectedResponse) {
            try await CaptionLoader(http: http).cues(for: track, userAgent: "test-agent")
        }
    }
}
