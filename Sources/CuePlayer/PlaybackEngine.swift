import Foundation

/// Plays one stream at a time. Implementations deliver events on the main actor.
@MainActor
public protocol PlaybackEngine: AnyObject {
    var onEvent: ((EngineEvent) -> Void)? { get set }
    func load(_ request: LoadRequest)
    func setPaused(_ paused: Bool)
    func perform(_ command: PlayerCommand)
    func stop()
}
