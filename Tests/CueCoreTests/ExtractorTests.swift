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
        let extractor = Extractor(
            http: http,
            selector: FormatSelector(maxShortSide: 1080, av1HardwareDecoding: false, vp9HardwareDecoding: false),
            solver: nil,
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )

        let resolution = try await extractor.resolve(videoID)

        #expect(resolution.title == "Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)")
        #expect(resolution.duration == 213)
        #expect(resolution.selection.video.codec == "avc1")
        #expect(resolution.selection.video.height == 1080)
        #expect(resolution.selection.audio.itag == 140)
        #expect(resolution.hlsManifestURL != nil)
        #expect(resolution.captionTracks.count == 6)
        #expect(resolution.expiresAt == Date(timeIntervalSince1970: 1_021_540))
        #expect(resolution.userAgent == ClientProfile.visionOS.userAgent)
    }

    @Test func resolvesChaptersFromTheWatchPage() async throws {
        let http = StubHTTPClient()
        http.on(path: "/watch", body: try Fixture.data("watch-page-chapters.html"))
        http.on(path: "/youtubei/v1/player", body: try Fixture.data("player-visionos-dQw4w9WgXcQ.json"))
        let extractor = Extractor(
            http: http,
            selector: FormatSelector(maxShortSide: 1080, av1HardwareDecoding: false, vp9HardwareDecoding: false),
            solver: nil
        )

        let resolution = try await extractor.resolve(videoID)

        #expect(resolution.chapters.map(\.title) == ["Intro", "The middle", "Outro"])
        #expect(resolution.chapters.last?.end == 213)
    }

    /// A page without markers falls back to the timestamps in the video's own description.
    @Test func fallsBackToDescriptionChapters() async throws {
        let fixture = try Fixture.data("player-visionos-dQw4w9WgXcQ.json")
        let original = Data(#""lengthSeconds": "213""#.utf8)
        let replacement = Data(#""lengthSeconds": "213", "shortDescription": "0:00 Intro\n1:00 Chorus""#.utf8)
        var body = fixture
        let range = try #require(body.range(of: original))
        body.replaceSubrange(range, with: replacement)

        let http = StubHTTPClient()
        http.on(path: "/watch", body: try Fixture.data("watch-page-snippet.html"))
        http.on(path: "/youtubei/v1/player", body: body)
        let extractor = Extractor(
            http: http,
            selector: FormatSelector(maxShortSide: 1080, av1HardwareDecoding: false, vp9HardwareDecoding: false),
            solver: nil
        )

        let resolution = try await extractor.resolve(videoID)

        #expect(resolution.chapters.map(\.title) == ["Intro", "Chorus"])
    }

    @Test func ignoresUnreadableExpiry() async throws {
        let fixture = try Fixture.data("player-visionos-dQw4w9WgXcQ.json")
        let original = Data(#""expiresInSeconds": "21540""#.utf8)
        let replacement = Data(#""expiresInSeconds": "soon""#.utf8)
        try #require(fixture.range(of: original) != nil)
        var body = fixture
        let range = try #require(body.range(of: original))
        body.replaceSubrange(range, with: replacement)

        let http = StubHTTPClient()
        http.on(path: "/watch", body: try Fixture.data("watch-page-snippet.html"))
        http.on(path: "/youtubei/v1/player", body: body)
        let extractor = Extractor(http: http, selector: FormatSelector(maxShortSide: 1080, av1HardwareDecoding: false, vp9HardwareDecoding: false), solver: nil)

        let resolution = try await extractor.resolve(videoID)

        #expect(resolution.expiresAt == nil)
    }

    @Test func sendsConsentCookieAndVisitorData() async throws {
        let http = try stubWithRealPlayer()
        _ = try await Extractor(http: http, selector: FormatSelector(maxShortSide: 1080, av1HardwareDecoding: false, vp9HardwareDecoding: false), solver: nil).resolve(videoID)

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
        _ = try await Extractor(http: http, selector: FormatSelector(maxShortSide: 1080, av1HardwareDecoding: false, vp9HardwareDecoding: false), solver: nil).resolve(videoID)

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

    @Test func resolvesVP9OnlyVideosWithSoftwareDecoding() async throws {
        let player = #"""
        {"playabilityStatus":{"status":"OK"},"streamingData":{"adaptiveFormats":[
        {"itag":248,"mimeType":"video/webm; codecs=\"vp9\"","bitrate":2500000,"width":1920,"height":1080,"url":"https://rr1.googlevideo.com/videoplayback?itag=248"},
        {"itag":140,"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":130000,"url":"https://rr1.googlevideo.com/videoplayback?itag=140"}
        ]}}
        """#
        let http = StubHTTPClient()
        http.on(path: "/watch", body: try Fixture.data("watch-page-snippet.html"))
        http.on(path: "/youtubei/v1/player", body: Data(player.utf8))
        let selector = FormatSelector(maxShortSide: 1080, av1HardwareDecoding: false, vp9HardwareDecoding: false)

        let resolution = try await Extractor(http: http, selector: selector, solver: nil).resolve(videoID)

        #expect(resolution.selection.video.itag == 248)
        #expect(resolution.selection.decoding == .software)
    }

    @Test func describesErrorsReadably() {
        #expect((ExtractionError.unplayable(status: "ERROR", reason: nil) as any Error).localizedDescription == "This video can't be played: ERROR.")
        #expect((ExtractionError.unplayable(status: "LOGIN_REQUIRED", reason: "Sign in") as any Error).localizedDescription == "This video can't be played: Sign in.")
        #expect((ExtractionError.httpStatus(403, InnerTube.playerURL) as any Error).localizedDescription == "YouTube returned HTTP 403 for https://www.youtube.com/youtubei/v1/player?prettyPrint=false.")
    }
}
