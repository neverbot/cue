import Foundation
import Testing
@testable import CueCore

@Suite struct PlayerResponseTests {
    @Test func decodesRealVisionOSResponse() throws {
        let response = try JSONDecoder().decode(PlayerResponse.self, from: Fixture.data("player-visionos-dQw4w9WgXcQ.json"))
        #expect(response.playabilityStatus.status == "OK")
        #expect(response.videoDetails?.title == "Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)")
        #expect(response.videoDetails?.lengthSeconds == "213")
        #expect(response.streamingData?.adaptiveFormats?.count == 27)
        #expect(response.streamingData?.hlsManifestUrl != nil)
        #expect(response.captions?.playerCaptionsTracklistRenderer?.captionTracks?.count == 6)
        #expect(response.storyboards?.playerStoryboardSpecRenderer?.spec.isEmpty == false)
    }

    @Test func decodesUnplayableResponse() throws {
        let json = #"{"playabilityStatus":{"status":"LOGIN_REQUIRED","reason":"Sign in to confirm you’re not a bot"}}"#
        let response = try JSONDecoder().decode(PlayerResponse.self, from: Data(json.utf8))
        #expect(response.playabilityStatus.status == "LOGIN_REQUIRED")
        #expect(response.playabilityStatus.reason == "Sign in to confirm you’re not a bot")
        #expect(response.streamingData == nil)
    }
}
