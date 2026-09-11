import Foundation

enum InnerTube {
    static let playerURL = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!
    static let origin = "https://www.youtube.com"

    /// Builds the `/player` request. Fixed client fields and `visitorData` override same-named keys in `client.extraContext`.
    static func playerRequest(videoID: VideoID, client: ClientProfile, visitorData: String, signatureTimestamp: Int?) throws -> HTTPRequest {
        var clientContext: [String: Any] = client.extraContext
        clientContext["clientName"] = client.clientName
        clientContext["clientVersion"] = client.clientVersion
        clientContext["userAgent"] = client.userAgent
        clientContext["hl"] = "en"
        clientContext["visitorData"] = visitorData

        var contentPlaybackContext: [String: Any] = ["html5Preference": "HTML5_PREF_WANTS"]
        if let signatureTimestamp {
            contentPlaybackContext["signatureTimestamp"] = signatureTimestamp
        }

        let body: [String: Any] = [
            "context": ["client": clientContext],
            "videoId": videoID.rawValue,
            "playbackContext": ["contentPlaybackContext": contentPlaybackContext],
            "contentCheckOk": true,
            "racyCheckOk": true,
        ]

        return HTTPRequest(
            url: playerURL,
            method: "POST",
            headers: [
                "Content-Type": "application/json",
                "User-Agent": client.userAgent,
                "Origin": origin,
                "X-YouTube-Client-Name": String(client.clientNameID),
                "X-YouTube-Client-Version": client.clientVersion,
                "X-Goog-Visitor-Id": visitorData,
            ],
            body: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        )
    }
}
