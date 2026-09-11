import Foundation
import Testing
@testable import CueCore

@Suite struct StreamFormatTests {
    func raw(_ json: String) throws -> PlayerResponse.RawFormat {
        try JSONDecoder().decode(PlayerResponse.RawFormat.self, from: Data(json.utf8))
    }

    @Test func mapsDirectVideoFormat() throws {
        let format = try #require(StreamFormat(raw: raw(#"{"itag":137,"mimeType":"video/mp4; codecs=\"avc1.640028\"","bitrate":4000000,"width":1920,"height":1080,"fps":30,"url":"https://rr1.googlevideo.com/videoplayback?itag=137&expire=1"}"#)))
        #expect(format.kind == .video)
        #expect(format.container == "mp4")
        #expect(format.codec == "avc1")
        #expect(format.height == 1080)
        #expect(format.needsChallenges == false)
    }

    @Test func normalisesVP9AndAudioCodecs() throws {
        let vp9 = try #require(StreamFormat(raw: raw(#"{"itag":248,"mimeType":"video/webm; codecs=\"vp09.00.40.08\"","bitrate":2000000,"height":1080,"url":"https://rr1.googlevideo.com/videoplayback?itag=248"}"#)))
        let opus = try #require(StreamFormat(raw: raw(#"{"itag":251,"mimeType":"audio/webm; codecs=\"opus\"","bitrate":150000,"url":"https://rr1.googlevideo.com/videoplayback?itag=251"}"#)))
        #expect(vp9.codec == "vp9")
        #expect(opus.kind == .audio)
        #expect(opus.codec == "opus")
        #expect(opus.container == "webm")
    }

    @Test func detectsSignatureAndNChallenges() throws {
        let format = try #require(StreamFormat(raw: raw(#"{"itag":137,"mimeType":"video/mp4; codecs=\"avc1.640028\"","bitrate":4000000,"height":1080,"signatureCipher":"s=AB%3DC&sp=sig&url=https%3A%2F%2Frr1.googlevideo.com%2Fvideoplayback%3Fitag%3D137%26n%3Dabc"}"#)))
        #expect(format.signatureChallenge == StreamFormat.SignatureChallenge(encrypted: "AB=C", parameter: "sig"))
        #expect(format.nChallenge == "abc")
        #expect(format.needsChallenges)
    }

    @Test func rejectsUnknownMimeTypes() throws {
        #expect(StreamFormat(raw: try raw(#"{"itag":1,"mimeType":"text/plain","url":"https://example.com"}"#)) == nil)
    }

    @Test(arguments: [
        #"{"itag":1,"url":"https://rr1.googlevideo.com/videoplayback?itag=1"}"#,
        #"{"itag":1,"mimeType":"","url":"https://rr1.googlevideo.com/videoplayback?itag=1"}"#,
        #"{"itag":1,"mimeType":";","url":"https://rr1.googlevideo.com/videoplayback?itag=1"}"#,
        #"{"itag":1,"mimeType":"video/","url":"https://rr1.googlevideo.com/videoplayback?itag=1"}"#,
    ])
    func rejectsMissingOrMalformedMimeTypes(_ json: String) throws {
        #expect(StreamFormat(raw: try raw(json)) == nil)
    }

    @Test func rewritesUrlWithSolvedChallenges() throws {
        let format = try #require(StreamFormat(raw: raw(#"{"itag":137,"mimeType":"video/mp4; codecs=\"avc1.640028\"","bitrate":1,"height":1080,"signatureCipher":"s=ABC&sp=sig&url=https%3A%2F%2Frr1.googlevideo.com%2Fvideoplayback%3Fitag%3D137%26n%3Dabc"}"#)))
        let solved = try #require(format.resolvingChallenges([.n: ["abc": "x+y="], .sig: ["ABC": "CBA/="]]))
        #expect(solved.needsChallenges == false)
        #expect(solved.url.absoluteString == "https://rr1.googlevideo.com/videoplayback?itag=137&n=x%2By%3D&sig=CBA%2F%3D")
    }

    @Test func refusesToRewriteWhenASolutionIsMissing() throws {
        let format = try #require(StreamFormat(raw: raw(#"{"itag":140,"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":1,"url":"https://rr1.googlevideo.com/videoplayback?itag=140&n=zzz"}"#)))
        #expect(format.resolvingChallenges([.n: [:]]) == nil)
    }

    @Test func normalisesAV1AndAACCodecs() throws {
        let av1 = try #require(StreamFormat(raw: raw(#"{"itag":399,"mimeType":"video/mp4; codecs=\"av01.0.08M.08\"","bitrate":3000000,"height":1080,"url":"https://rr1.googlevideo.com/videoplayback?itag=399"}"#)))
        let aac = try #require(StreamFormat(raw: raw(#"{"itag":140,"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":130000,"url":"https://rr1.googlevideo.com/videoplayback?itag=140"}"#)))
        #expect(av1.codec == "av01")
        #expect(aac.codec == "mp4a")
    }

    @Test func defaultsSignatureParameterWhenMissingOrEmpty() throws {
        let missing = try #require(StreamFormat(raw: raw(#"{"itag":137,"mimeType":"video/mp4; codecs=\"avc1.640028\"","signatureCipher":"s=ABC&url=https%3A%2F%2Frr1.googlevideo.com%2Fvideoplayback%3Fitag%3D137"}"#)))
        let empty = try #require(StreamFormat(raw: raw(#"{"itag":137,"mimeType":"video/mp4; codecs=\"avc1.640028\"","signatureCipher":"s=ABC&sp=&url=https%3A%2F%2Frr1.googlevideo.com%2Fvideoplayback%3Fitag%3D137"}"#)))
        #expect(missing.signatureChallenge?.parameter == "signature")
        #expect(empty.signatureChallenge?.parameter == "signature")
    }

    @Test func rejectsFormatsWithoutAbsoluteURL() throws {
        #expect(StreamFormat(raw: try raw(#"{"itag":1,"mimeType":"video/mp4; codecs=\"avc1.1\"","url":"not a url"}"#)) == nil)
        #expect(StreamFormat(raw: try raw(#"{"itag":1,"mimeType":"video/mp4; codecs=\"avc1.1\"","url":"/videoplayback?itag=1"}"#)) == nil)
    }

    @Test func encodesArbitrarySolverOutput() throws {
        let format = try #require(StreamFormat(raw: raw(#"{"itag":137,"mimeType":"video/mp4; codecs=\"avc1.640028\"","signatureCipher":"s=ABC&sp=sig&url=https%3A%2F%2Frr1.googlevideo.com%2Fvideoplayback%3Fitag%3D137%26n%3Dabc"}"#)))
        let solved = try #require(format.resolvingChallenges([.n: ["abc": "a%b c"], .sig: ["ABC": "#ñ"]]))
        #expect(solved.url.absoluteString == "https://rr1.googlevideo.com/videoplayback?itag=137&n=a%25b%20c&sig=%23%C3%B1")
    }

    @Test func survivesHostileSignatureParameterNames() throws {
        let format = try #require(StreamFormat(raw: raw(#"{"itag":137,"mimeType":"video/mp4; codecs=\"avc1.640028\"","signatureCipher":"s=ABC&sp=a%20b&url=https%3A%2F%2Frr1.googlevideo.com%2Fvideoplayback%3Fitag%3D137"}"#)))
        let solved = try #require(format.resolvingChallenges([.sig: ["ABC": "CBA"]]))
        #expect(solved.url.absoluteString == "https://rr1.googlevideo.com/videoplayback?itag=137&a%20b=CBA")
    }

    @Test func rewritesNOnlyURLInPlace() throws {
        let format = try #require(StreamFormat(raw: raw(#"{"itag":140,"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","bitrate":1,"url":"https://rr1.googlevideo.com/videoplayback?itag=140&n=zzz&expire=1"}"#)))
        let solved = try #require(format.resolvingChallenges([.n: ["zzz": "yyy"]]))
        #expect(solved.url.absoluteString == "https://rr1.googlevideo.com/videoplayback?itag=140&n=yyy&expire=1")
    }

    @Test func refusesToRewriteWhenSignatureSolutionIsMissing() throws {
        let format = try #require(StreamFormat(raw: raw(#"{"itag":137,"mimeType":"video/mp4; codecs=\"avc1.640028\"","signatureCipher":"s=ABC&sp=sig&url=https%3A%2F%2Frr1.googlevideo.com%2Fvideoplayback%3Fitag%3D137%26n%3Dabc"}"#)))
        #expect(format.resolvingChallenges([.n: ["abc": "cba"]]) == nil)
    }

    @Test(arguments: [
        "http://rr1.googlevideo.com/videoplayback?itag=140",
        "mailto:x",
    ])
    func rejectsNonHTTPSURLs(_ url: String) throws {
        #expect(StreamFormat(raw: try raw(#"{"itag":140,"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","url":"\#(url)"}"#)) == nil)
    }

    @Test func refusesSignatureParameterThatCollidesWithQuery() throws {
        let format = try #require(StreamFormat(raw: raw(#"{"itag":137,"mimeType":"video/mp4; codecs=\"avc1.640028\"","signatureCipher":"s=ABC&sp=n&url=https%3A%2F%2Frr1.googlevideo.com%2Fvideoplayback%3Fitag%3D137%26n%3Dabc"}"#)))
        #expect(format.resolvingChallenges([.n: ["abc": "cba"], .sig: ["ABC": "CBA"]]) == nil)
    }

    @Test func refusesEmptySolutions() throws {
        let nOnly = try #require(StreamFormat(raw: raw(#"{"itag":140,"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","url":"https://rr1.googlevideo.com/videoplayback?itag=140&n=zzz"}"#)))
        let sigOnly = try #require(StreamFormat(raw: raw(#"{"itag":137,"mimeType":"video/mp4; codecs=\"avc1.640028\"","signatureCipher":"s=ABC&sp=sig&url=https%3A%2F%2Frr1.googlevideo.com%2Fvideoplayback%3Fitag%3D137"}"#)))
        #expect(nOnly.resolvingChallenges([.n: ["zzz": ""]]) == nil)
        #expect(sigOnly.resolvingChallenges([.sig: ["ABC": ""]]) == nil)
    }

    @Test func refusesDuplicateNParameters() throws {
        let format = try #require(StreamFormat(raw: raw(#"{"itag":140,"mimeType":"audio/mp4; codecs=\"mp4a.40.2\"","url":"https://rr1.googlevideo.com/videoplayback?itag=140&n=abc&n=def"}"#)))
        #expect(format.resolvingChallenges([.n: ["abc": "cba", "def": "fed"]]) == nil)
    }
}
