import Foundation
import Testing
@testable import CueCore

@Suite struct CaptionTrackTests {
    func tracks(from json: String) throws -> [CaptionTrack] {
        let response = try JSONDecoder().decode(PlayerResponse.self, from: Data(json.utf8))
        return CaptionTrack.list(in: response.captions)
    }

    func fixtureTracks() throws -> [CaptionTrack] {
        let response = try JSONDecoder().decode(PlayerResponse.self, from: Fixture.data("player-visionos-dQw4w9WgXcQ.json"))
        return CaptionTrack.list(in: response.captions)
    }

    /// A tracklist with the fields the live response carries, wrapped in the smallest response that decodes.
    func response(tracks: String) -> String {
        #"{"playabilityStatus":{"status":"OK"},"captions":{"playerCaptionsTracklistRenderer":{"captionTracks":[\#(tracks)]}}}"#
    }

    @Test func readsEveryTrackInTheFixture() throws {
        let tracks = try fixtureTracks()
        #expect(tracks.count == 6)
        #expect(tracks.first?.languageCode == "en")
        #expect(tracks.contains { $0.languageCode == "pt-BR" })
    }

    @Test func marksAutomaticTracks() throws {
        let tracks = try fixtureTracks()
        #expect(tracks.filter(\.isAutomatic).count == 1)
        #expect(tracks.filter(\.isAutomatic).first?.languageCode == "en")
    }

    @Test func prefersTheGivenNameOverTheLanguageCode() throws {
        let tracks = try self.tracks(from: response(tracks:
            #"{"baseUrl":"https://www.youtube.com/api/timedtext?lang=de","languageCode":"de","name":{"simpleText":"German"}}"#))
        #expect(tracks.first?.displayName == "German")
    }

    @Test func fallsBackToTheLanguageCode() throws {
        let tracks = try self.tracks(from: response(tracks:
            #"{"baseUrl":"https://www.youtube.com/api/timedtext?lang=de","languageCode":"de"}"#))
        #expect(tracks.first?.displayName == "de")
    }

    @Test func joinsNameRuns() throws {
        let tracks = try self.tracks(from: response(tracks:
            #"{"baseUrl":"https://www.youtube.com/api/timedtext?lang=de","languageCode":"de","name":{"runs":[{"text":"German"},{"text":" (Germany)"}]}}"#))
        #expect(tracks.first?.displayName == "German (Germany)")
    }

    @Test func labelsAutomaticTracksInTheMenu() throws {
        let tracks = try self.tracks(from: response(tracks:
            #"{"baseUrl":"https://www.youtube.com/api/timedtext?lang=en","languageCode":"en","kind":"asr","name":{"simpleText":"English"}}"#))
        #expect(tracks.first?.menuTitle == "English (automatic)")
    }

    @Test func skipsATrackWithoutAUsableURL() throws {
        #expect(try tracks(from: response(tracks: #"{"languageCode":"en"}"#)).isEmpty)
    }

    @Test func skipsATrackWithoutALanguageCode() throws {
        #expect(try tracks(from: response(tracks: #"{"baseUrl":"https://www.youtube.com/api/timedtext?lang=en"}"#)).isEmpty)
    }

    @Test func addsTheFormatToTheURL() throws {
        let track = try #require(try fixtureTracks().first)
        #expect(track.url(format: .json3).query?.contains("fmt=json3") == true)
        #expect(track.url(format: .vtt).query?.contains("fmt=vtt") == true)
    }

    @Test func replacesAFormatTheURLAlreadyCarries() throws {
        let tracks = try self.tracks(from: response(tracks:
            #"{"baseUrl":"https://www.youtube.com/api/timedtext?lang=en&fmt=srv3","languageCode":"en"}"#))
        let url = try #require(tracks.first).url(format: .json3)
        #expect(url.absoluteString == "https://www.youtube.com/api/timedtext?lang=en&fmt=json3")
    }

    /// A language usually appears twice — the author's track and YouTube's automatic one — so the two must not
    /// collide in a list, a menu or a file name.
    @Test func tellsAutomaticAndManualTracksApart() throws {
        let tracks = try fixtureTracks().filter { $0.languageCode == "en" }
        #expect(tracks.count == 2)
        #expect(Set(tracks.map(\.id)).count == 2)
    }
}
