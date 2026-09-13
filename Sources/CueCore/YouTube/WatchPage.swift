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

    /// The `ytInitialData` object embedded in the watch page, as JSON.
    ///
    /// Scanned rather than matched with a regular expression: the object is a megabyte of nested JSON containing both
    /// braces and quotes inside strings, and no regular expression can find its end. The scan tracks string state and
    /// escapes, and stops at the brace that closes the object.
    static func initialData(in html: String) -> Data? {
        guard let marker = html.range(of: "ytInitialData"),
              let start = html[marker.upperBound...].firstIndex(of: "{")
        else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < html.endIndex {
            let character = html[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return Data(html[start...index].utf8)
                }
            }
            index = html.index(after: index)
        }
        return nil
    }
}
