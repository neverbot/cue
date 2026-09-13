import CueCore
import CuePlayer
import Foundation

/// What the queue needs from the player. `PlayerController` conforms (see `QueueCoordinator.swift`); tests use a
/// stand-in, so the queue's playback rules are testable without libmpv.
///
/// It lives in its own file because the test fakes conform to it before the coordinator exists.
@MainActor
public protocol QueuePlaying: AnyObject {
    var playerState: PlayerState { get }
    func open(_ input: LaunchInput) async
}
