import Foundation

enum PlayerScript {
    static let iframeAPIURL = URL(string: "https://www.youtube.com/iframe_api")!

    static func playerID(inIframeAPI js: String) -> String? {
        firstCapture(#"player\\?/([0-9a-fA-F]{8})\\?/"#, in: js)
    }

    static func baseJSURL(playerID: String) -> URL {
        URL(string: "https://www.youtube.com/s/player/\(playerID)/player_ias.vflset/en_US/base.js")!
    }

    static func signatureTimestamp(inPlayerJS js: String) -> Int? {
        firstCapture(#"(?:signatureTimestamp|sts)\s*:\s*([0-9]{5})"#, in: js).flatMap(Int.init)
    }
}
