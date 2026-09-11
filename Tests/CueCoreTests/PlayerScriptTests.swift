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

    @Test func findsUnescapedPlayerID() {
        #expect(PlayerScript.playerID(inIframeAPI: "https://www.youtube.com/s/player/8c3fda2d/www-widgetapi.vflset/www-widgetapi.js") == "8c3fda2d")
    }

    @Test func ignoresScriptsWithoutPlayer() {
        #expect(PlayerScript.playerID(inIframeAPI: "no player here") == nil)
    }

    @Test func acceptsHexPlayerIDsOfEightOrMoreDigits() {
        #expect(PlayerScript.playerID(inIframeAPI: #"\/s\/player\/8c3fda2d1\/"#) == "8c3fda2d1")
        #expect(PlayerScript.playerID(inIframeAPI: #"\/s\/player\/8c3fda2\/"#) == nil)
    }

    @Test func prefersTheStaticPlayerPath() {
        let js = #"u='/embed/player/deadbeef/'; var scriptUrl = 'https:\/\/www.youtube.com\/s\/player\/8c3fda2d\/www-widgetapi.vflset\/www-widgetapi.js';"#
        #expect(PlayerScript.playerID(inIframeAPI: js) == "8c3fda2d")
    }

    @Test func findsSignatureTimestampVariants() {
        #expect(PlayerScript.signatureTimestamp(inPlayerJS: "x={sts:20702}") == 20702)
        #expect(PlayerScript.signatureTimestamp(inPlayerJS: "x={signatureTimestamp \n :  20702}") == 20702)
    }
}
