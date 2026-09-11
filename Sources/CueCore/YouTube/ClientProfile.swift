import Foundation

/// One InnerTube client identity. Values mirror yt-dlp's `INNERTUBE_CLIENTS`
/// (yt_dlp/extractor/youtube/_base.py); YouTube rotates which clients work.
public struct ClientProfile: Sendable, Equatable {
    public let key: String
    public let clientNameID: Int
    public let clientName: String
    public let clientVersion: String
    public let userAgent: String
    public let extraContext: [String: String]
    public let requiresPlayerJS: Bool

    public static let visionOS = ClientProfile(
        key: "visionos",
        clientNameID: 101,
        clientName: "VISIONOS",
        clientVersion: "1.02",
        userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
        extraContext: [
            "deviceMake": "Apple",
            "deviceModel": "RealityDevice17,1",
            "osName": "visionOS",
            "osVersion": "26.5.23O471",
        ],
        requiresPlayerJS: false
    )
}
