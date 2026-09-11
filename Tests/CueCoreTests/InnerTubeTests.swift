import Foundation
import Testing
@testable import CueCore

@Suite struct InnerTubeTests {
    let videoID = VideoID("dQw4w9WgXcQ")!

    @Test func buildsPlayerRequestHeaders() throws {
        let request = try InnerTube.playerRequest(videoID: videoID, client: .visionOS, visitorData: "VD123", signatureTimestamp: nil)
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")
        #expect(request.headers["X-YouTube-Client-Name"] == "101")
        #expect(request.headers["X-YouTube-Client-Version"] == "1.02")
        #expect(request.headers["X-Goog-Visitor-Id"] == "VD123")
        #expect(request.headers["User-Agent"] == ClientProfile.visionOS.userAgent)
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(request.headers["Origin"] == "https://www.youtube.com")
    }

    @Test func buildsPlayerRequestBody() throws {
        let request = try InnerTube.playerRequest(videoID: videoID, client: .visionOS, visitorData: "VD123", signatureTimestamp: 20312)
        let bodyData = try #require(request.body)
        let body = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let client = try #require((body["context"] as? [String: Any])?["client"] as? [String: Any])
        #expect(client["clientName"] as? String == "VISIONOS")
        #expect(client["visitorData"] as? String == "VD123")
        #expect(client["hl"] as? String == "en")
        #expect(body["videoId"] as? String == "dQw4w9WgXcQ")
        #expect(body["contentCheckOk"] as? Bool == true)
        let playback = try #require((body["playbackContext"] as? [String: Any])?["contentPlaybackContext"] as? [String: Any])
        #expect(playback["signatureTimestamp"] as? Int == 20312)
        #expect(playback["html5Preference"] as? String == "HTML5_PREF_WANTS")
    }

    @Test func omitsSignatureTimestampWhenUnknown() throws {
        let request = try InnerTube.playerRequest(videoID: videoID, client: .visionOS, visitorData: "VD123", signatureTimestamp: nil)
        let bodyData = try #require(request.body)
        let body = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let playback = try #require((body["playbackContext"] as? [String: Any])?["contentPlaybackContext"] as? [String: Any])
        #expect(playback["signatureTimestamp"] == nil)
    }

    @Test func encodesExactWireBody() throws {
        let request = try InnerTube.playerRequest(videoID: videoID, client: .visionOS, visitorData: "VD123", signatureTimestamp: 20312)
        let bodyData = try #require(request.body)
        let expected = #"{"contentCheckOk":true,"context":{"client":{"clientName":"VISIONOS","clientVersion":"1.02","deviceMake":"Apple","deviceModel":"RealityDevice17,1","hl":"en","osName":"visionOS","osVersion":"26.5.23O471","userAgent":"Mozilla\/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit\/605.1.15 (KHTML, like Gecko) Version\/26.0 Safari\/605.1.15","visitorData":"VD123"}},"playbackContext":{"contentPlaybackContext":{"html5Preference":"HTML5_PREF_WANTS","signatureTimestamp":20312}},"racyCheckOk":true,"videoId":"dQw4w9WgXcQ"}"#
        #expect(String(decoding: bodyData, as: UTF8.self) == expected)
    }
}
