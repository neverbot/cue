import Foundation
import Testing
@testable import CueCore

@Suite struct PlayerResponseTests {
    @Test func decodesRealVisionOSResponse() throws {
        let response = try JSONDecoder().decode(PlayerResponse.self, from: Fixture.data("player-visionos-dQw4w9WgXcQ.json"))
        #expect(response.playabilityStatus.status == "OK")
        #expect(response.videoDetails?.title == "Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)")
        #expect(response.videoDetails?.lengthSeconds == "213")
        #expect(response.videoDetails?.author == "Rick Astley")
        #expect(response.streamingData?.adaptiveFormats?.count == 27)
        #expect(response.streamingData?.hlsManifestUrl != nil)
        #expect(response.captions?.playerCaptionsTracklistRenderer?.captionTracks?.count == 6)
        #expect(response.storyboards?.playerStoryboardSpecRenderer?.spec?.isEmpty == false)

        let firstFormat = try #require(response.streamingData?.adaptiveFormats?.first)
        #expect(firstFormat.itag == 313)
        #expect(firstFormat.height == 2160)
        #expect(firstFormat.fps == 25)
        #expect(firstFormat.bitrate == 18076636)
        #expect(firstFormat.url != nil)
    }

    @Test func decodesUnplayableResponse() throws {
        let json = #"{"playabilityStatus":{"status":"LOGIN_REQUIRED","reason":"Sign in to confirm you’re not a bot"}}"#
        let response = try JSONDecoder().decode(PlayerResponse.self, from: Data(json.utf8))
        #expect(response.playabilityStatus.status == "LOGIN_REQUIRED")
        #expect(response.playabilityStatus.reason == "Sign in to confirm you’re not a bot")
        #expect(response.streamingData == nil)
    }

    @Test func decodesPartialResponses() throws {
        let json = #"""
        {
          "playabilityStatus": {"status": "UNPLAYABLE", "reason": "Private video"},
          "videoDetails": {"author": "Someone"},
          "streamingData": {"adaptiveFormats": [{"itag": 137}, {"itag": 140, "mimeType": "audio/mp4; codecs=\"mp4a.40.2\""}]},
          "captions": {"playerCaptionsTracklistRenderer": {"captionTracks": [{"kind": "asr"}]}},
          "storyboards": {"playerStoryboardSpecRenderer": {}}
        }
        """#
        let response = try JSONDecoder().decode(PlayerResponse.self, from: Data(json.utf8))
        #expect(response.playabilityStatus.status == "UNPLAYABLE")
        #expect(response.videoDetails?.title == nil)
        #expect(response.videoDetails?.author == "Someone")
        #expect(response.streamingData?.adaptiveFormats?.count == 2)
        #expect(response.streamingData?.adaptiveFormats?.first?.mimeType == nil)
        #expect(response.captions?.playerCaptionsTracklistRenderer?.captionTracks?.first?.baseUrl == nil)
        #expect(response.storyboards?.playerStoryboardSpecRenderer?.spec == nil)
    }
}
