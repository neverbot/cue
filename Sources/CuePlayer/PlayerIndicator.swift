import Foundation

/// What belongs in the middle of the picture right now.
///
/// One rule rather than three conditions spread through the view, because these states overlap in ways that are
/// easy to get wrong: a video can be paused *and* buffering, ready *and* stalled, resolving with a message
/// already on screen. Deciding it here means it can be tested; `Sources/Cue` has no automated coverage by design.
public enum PlayerIndicator: Equatable, Sendable {
    /// The picture speaks for itself.
    case none
    /// Something is happening that the viewer cannot see: a stream being found, a file being opened, or playback
    /// waiting on the network. Without this the window is simply black, which is indistinguishable from an app
    /// that has hung.
    case loading
    /// Playback is paused, so a still frame is not mistaken for a stalled one.
    case paused

    public static func current(for state: PlayerState) -> PlayerIndicator {
        switch state.phase {
        case .resolving, .loading:
            .loading
        case .ready:
            // A pause the viewer asked for wins over buffering. They know why it stopped, and a spinner would
            // suggest the app is doing something about it when it is waiting for them.
            state.isPaused ? .paused : (state.isBuffering ? .loading : .none)
        case .idle, .ended, .failed:
            // Each of these has words of its own in the centre — an invitation, or a reason it failed — and a
            // symbol on top of a sentence says less than the sentence alone.
            .none
        }
    }
}
