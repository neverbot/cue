import Foundation

/// Whether adding videos should also start playing one.
///
/// A rule rather than a boolean at each call site, because it is the kind of decision that gets re-argued: pasting
/// a link, clicking a bookmarklet and dropping a link all mean the same thing, and all three used to behave
/// differently depending on what the player happened to be doing.
public enum QueueAddPlayback {
    /// Adding **one** video is an instruction to watch it: it jumps there and starts, interrupting whatever was
    /// playing. That is what someone means by pasting a link or clicking a bookmarklet, and it holds even when the
    /// video was already in the queue — asking for a video that is already on the list is still asking for it.
    ///
    /// Adding **several** at once is the opposite gesture: filing them. Twenty tabs handed over by the browser, or
    /// a pasted block of links, are a queue to get through later, and hijacking playback to start an arbitrary one
    /// of them would be an interruption nobody asked for. They still start playing when nothing is on, since an
    /// idle player with a fresh queue has nothing better to do.
    public static func shouldPlay(addedCount: Int, isPlaying: Bool) -> Bool {
        switch addedCount {
        case 0: false
        case 1: true
        default: !isPlaying
        }
    }
}
