@testable import CueQueue
import Testing

@Suite struct QueueAddPlaybackTests {
    @Test func oneVideoIsAnInstructionToWatchItNow() {
        // Even mid-video: pasting a link or clicking the bookmarklet means "this one, now".
        #expect(QueueAddPlayback.shouldPlay(addedCount: 1, isPlaying: true))
        #expect(QueueAddPlayback.shouldPlay(addedCount: 1, isPlaying: false))
    }

    @Test func severalVideosAreFiledRatherThanPlayedOverWhatIsOn() {
        #expect(!QueueAddPlayback.shouldPlay(addedCount: 2, isPlaying: true))
        #expect(!QueueAddPlayback.shouldPlay(addedCount: 20, isPlaying: true))
    }

    @Test func severalVideosStartAnIdlePlayer() {
        #expect(QueueAddPlayback.shouldPlay(addedCount: 2, isPlaying: false))
        #expect(QueueAddPlayback.shouldPlay(addedCount: 20, isPlaying: false))
    }

    @Test func nothingAddedPlaysNothing() {
        #expect(!QueueAddPlayback.shouldPlay(addedCount: 0, isPlaying: false))
        #expect(!QueueAddPlayback.shouldPlay(addedCount: 0, isPlaying: true))
    }
}
