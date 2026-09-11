@testable import CuePlayer
import Foundation
import Testing

@Suite struct PlaybackSupportTests {
    @Test func redactsStreamURLs() {
        let line = "Cannot open file 'https://rr1---sn-test.googlevideo.com/videoplayback?expire=1&ip=0.0.0.0': error"
        #expect(LogRedactor.redact(line) == "Cannot open file '<url>': error")
        #expect(LogRedactor.redact("audio: aac 44100 Hz") == "audio: aac 44100 Hz")
    }

    @Test func formatsPlaybackTimes() {
        #expect(PlaybackTime.format(0) == "0:00")
        #expect(PlaybackTime.format(59.9) == "0:59")
        #expect(PlaybackTime.format(61) == "1:01")
        #expect(PlaybackTime.format(3600) == "1:00:00")
        #expect(PlaybackTime.format(3723) == "1:02:03")
        #expect(PlaybackTime.format(-5) == "0:00")
        #expect(PlaybackTime.format(.nan) == "0:00")
    }

    @Test func refreshesStreamsCloseToExpiry() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(!StreamFreshness.needsRefresh(expiresAt: nil, now: now))
        #expect(!StreamFreshness.needsRefresh(expiresAt: now.addingTimeInterval(3600), now: now))
        #expect(StreamFreshness.needsRefresh(expiresAt: now.addingTimeInterval(100), now: now))
        #expect(StreamFreshness.needsRefresh(expiresAt: now.addingTimeInterval(-1), now: now))
    }
}
