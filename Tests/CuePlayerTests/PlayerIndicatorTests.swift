@testable import CuePlayer
import Testing

@Suite struct PlayerIndicatorTests {
    private func state(
        _ phase: PlayerState.Phase,
        paused: Bool = false,
        buffering: Bool = false
    ) -> PlayerState {
        var state = PlayerState()
        state.phase = phase
        state.isPaused = paused
        state.isBuffering = buffering
        return state
    }

    @Test func showsTheSpinnerWhileAStreamIsBeingFoundAndOpened() {
        #expect(PlayerIndicator.current(for: state(.resolving)) == .loading)
        // The gap this was written for: nothing at all used to be shown here, so the window was simply black.
        #expect(PlayerIndicator.current(for: state(.loading)) == .loading)
    }

    @Test func showsTheSpinnerWhilePlaybackWaitsOnTheNetwork() {
        #expect(PlayerIndicator.current(for: state(.ready, buffering: true)) == .loading)
    }

    @Test func showsThePlayGlyphWhilePaused() {
        #expect(PlayerIndicator.current(for: state(.ready, paused: true)) == .paused)
    }

    @Test func aPauseTheViewerAskedForWinsOverBuffering() {
        // They know why it stopped; a spinner would claim the app is working on it.
        #expect(PlayerIndicator.current(for: state(.ready, paused: true, buffering: true)) == .paused)
    }

    @Test func showsNothingOverAPictureThatIsPlaying() {
        #expect(PlayerIndicator.current(for: state(.ready)) == .none)
    }

    @Test func leavesTheCentreToTheStatesThatHaveWordsOfTheirOwn() {
        #expect(PlayerIndicator.current(for: state(.idle)) == .none)
        #expect(PlayerIndicator.current(for: state(.ended)) == .none)
        #expect(PlayerIndicator.current(for: state(.failed("No streams"))) == .none)
    }
}
