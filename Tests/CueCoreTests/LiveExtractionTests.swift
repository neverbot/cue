import Foundation
import Testing
@testable import CueCore

@Suite(.enabled(if: ProcessInfo.processInfo.environment["CUE_LIVE_TESTS"] == "1"))
struct LiveExtractionTests {
    @Test(arguments: ["dQw4w9WgXcQ", "jNQXAC9IVRw"])
    func resolvesRealVideos(_ id: String) async throws {
        let videoID = try #require(VideoID(id))
        let solver = try ChallengeSolver(scriptsDirectory: ChallengeSolverTests.scriptsDirectory)
        let extractor = Extractor(selector: FormatSelector(maxShortSide: 1080, av1HardwareDecoding: false), solver: solver)
        let resolution = try await extractor.resolve(videoID)
        #expect(resolution.selection.video.codec == "avc1")
        #expect(resolution.selection.audio.codec == "mp4a")

        var probe = URLRequest(url: resolution.selection.audio.url)
        probe.setValue(resolution.userAgent, forHTTPHeaderField: "User-Agent")
        probe.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        let (_, response) = try await URLSession.shared.data(for: probe)
        #expect([200, 206].contains((response as? HTTPURLResponse)?.statusCode ?? 0))
    }
}
