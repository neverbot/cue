import Testing
@testable import CueCore

@Suite struct PlayerScriptTests {
    @Test func findsPlayerIDInIframeAPI() {
        let js = #"var scriptUrl = 'https:\/\/www.youtube.com\/s\/player\/8c3fda2d\/www-widgetapi.vflset\/www-widgetapi.js';"#
        #expect(PlayerScript.playerID(inIframeAPI: js) == "8c3fda2d")
    }

    @Test func buildsBaseJSURL() {
        #expect(PlayerScript.baseJSURL(playerID: "8c3fda2d").absoluteString == "https://www.youtube.com/s/player/8c3fda2d/player_ias.vflset/en_US/base.js")
    }

    @Test func findsSignatureTimestamp() {
        #expect(PlayerScript.signatureTimestamp(inPlayerJS: "a={foo:1,signatureTimestamp:20312,bar:2}") == 20312)
        #expect(PlayerScript.signatureTimestamp(inPlayerJS: "no timestamp here") == nil)
    }
}
