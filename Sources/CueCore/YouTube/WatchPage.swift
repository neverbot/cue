import Foundation

enum WatchPage {
    /// Cookie that skips the EU consent interstitial.
    static let consentCookie = "SOCS=CAI"

    static func url(for videoID: VideoID) -> URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoID.rawValue)&bpctr=9999999999&has_verified=1")!
    }

    static func visitorData(in html: String) -> String? {
        firstCapture(#""VISITOR_DATA"\s*:\s*"([^"]+)""#, in: html)
    }
}
