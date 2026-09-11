import Foundation
import Testing
@testable import CueCore

@Suite struct ExtractorTests {
    let videoID = VideoID("dQw4w9WgXcQ")!

    func stubWithRealPlayer() throws -> StubHTTPClient {
        let http = StubHTTPClient()
        http.on(path: "/watch", body: try Fixture.data("watch-page-snippet.html"))
        http.on(path: "/youtubei/v1/player", body: try Fixture.data("player-visionos-dQw4w9WgXcQ.json"))
        return http
    }

    @Test func resolvesPlayableStreams() async throws {
        let http = try stubWithRealPlayer()
        let extractor = Extractor(http: http, selector: FormatSelector(maxHeight: 1080, av1HardwareDecoding: false), solver: nil)

        let resolution = try await extractor.resolve(videoID)

        #expect(resolution.title == "Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)")
        #expect(resolution.duration == 213)
        #expect(resolution.selection.video.codec == "avc1")
        #expect(resolution.selection.video.height == 1080)
        #expect(resolution.selection.audio.itag == 140)
        #expect(resolution.hlsManifestURL != nil)
        #expect(resolution.captionTrackCount == 6)
        #expect(resolution.userAgent == ClientProfile.visionOS.userAgent)
    }

    @Test func sendsConsentCookieAndVisitorData() async throws {
        let http = try stubWithRealPlayer()
        _ = try await Extractor(http: http, selector: FormatSelector(maxHeight: 1080, av1HardwareDecoding: false), solver: nil).resolve(videoID)

        let requests = http.recorded
        #expect(requests.count == 2)
        #expect(requests[0].headers["Cookie"] == "SOCS=CAI")
        #expect(requests[1].headers["X-Goog-Visitor-Id"] == "CgtTRVNUVklTSVRPUg%3D%3D")
    }

    @Test func reportsUnplayableVideos() async throws {
        let http = StubHTTPClient()
        http.on(path: "/watch", body: try Fixture.data("watch-page-snippet.html"))
        http.on(path: "/youtubei/v1/player", body: Data(#"{"playabilityStatus":{"status":"LOGIN_REQUIRED","reason":"Sign in"}}"#.utf8))

        await #expect(throws: ExtractionError.unplayable(status: "LOGIN_REQUIRED", reason: "Sign in")) {
            try await Extractor(http: http, solver: nil).resolve(videoID)
        }
    }

    @Test func reportsMissingVisitorData() async throws {
        let http = StubHTTPClient()
        http.on(path: "/watch", body: Data("<html>consent</html>".utf8))

        await #expect(throws: ExtractionError.visitorDataNotFound) {
            try await Extractor(http: http, solver: nil).resolve(videoID)
        }
    }

    @Test func reportsHTTPErrors() async throws {
        let http = StubHTTPClient()
        http.on(path: "/watch", status: 429, body: Data())

        await #expect(throws: ExtractionError.httpStatus(429, WatchPage.url(for: videoID))) {
            try await Extractor(http: http, solver: nil).resolve(videoID)
        }
    }

    @Test func reportsUnexpectedResponses() async throws {
        let http = StubHTTPClient()
        http.on(path: "/watch", body: try Fixture.data("watch-page-snippet.html"))
        http.on(path: "/youtubei/v1/player", body: Data(#"{"unexpected":true}"#.utf8))

        await #expect(throws: ExtractionError.unexpectedResponse) {
            try await Extractor(http: http, solver: nil).resolve(videoID)
        }
    }

    @Test func sendsWatchAndPlayerRequests() async throws {
        let http = try stubWithRealPlayer()
        _ = try await Extractor(http: http, selector: FormatSelector(maxHeight: 1080, av1HardwareDecoding: false), solver: nil).resolve(videoID)

        let requests = http.recorded
        try #require(requests.count == 2)
        #expect(requests[0].method == "GET")
        #expect(requests[0].headers["User-Agent"] == ClientProfile.visionOS.userAgent)
        #expect(requests[1].method == "POST")
        #expect(requests[1].url == InnerTube.playerURL)
    }

    @Test func reportsPlayerHTTPErrors() async throws {
        let http = StubHTTPClient()
        http.on(path: "/watch", body: try Fixture.data("watch-page-snippet.html"))
        http.on(path: "/youtubei/v1/player", status: 403, body: Data())

        await #expect(throws: ExtractionError.httpStatus(403, InnerTube.playerURL)) {
            try await Extractor(http: http, solver: nil).resolve(videoID)
        }
    }

    @Test func reportsMissingFormats() async throws {
        let http = StubHTTPClient()
        http.on(path: "/watch", body: try Fixture.data("watch-page-snippet.html"))
        http.on(path: "/youtubei/v1/player", body: Data(#"{"playabilityStatus":{"status":"OK"}}"#.utf8))

        await #expect(throws: ExtractionError.noPlayableFormats) {
            try await Extractor(http: http, solver: nil).resolve(videoID)
        }
    }

    @Test func describesErrorsReadably() {
        #expect(ExtractionError.unplayable(status: "ERROR", reason: nil).errorDescription == "This video can't be played: ERROR.")
        #expect(ExtractionError.unplayable(status: "LOGIN_REQUIRED", reason: "Sign in").errorDescription == "This video can't be played: Sign in.")
        #expect(ExtractionError.httpStatus(403, InnerTube.playerURL).errorDescription == "YouTube returned HTTP 403 for https://www.youtube.com/youtubei/v1/player?prettyPrint=false.")
    }
}
