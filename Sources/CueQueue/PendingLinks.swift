import Foundation

/// Links that arrived before the app was ready for them.
///
/// Clicking the bookmarklet with Cue closed launches it *and* delivers the `cue://add` URL, and macOS does not
/// wait: the event can arrive while the database is still opening and libmpv is still starting, which is before
/// there is any window to hand it to. Dropping it there is invisible — the app opens, looking like it worked, and
/// the video is simply gone.
///
/// So the URL is held instead, and handed over as soon as the window exists. Held, not handled: this type knows
/// nothing about videos or queues, only that nothing may be lost and nothing may be delivered twice.
public struct PendingLinks: Equatable, Sendable {
    private var urls: [URL] = []

    public init() {}

    public var isEmpty: Bool { urls.isEmpty }

    public mutating func hold(_ url: URL) {
        urls.append(url)
    }

    /// Everything held, in the order it arrived, and empties the store in the same breath — so a second flush
    /// cannot add the same video twice.
    public mutating func takeAll() -> [URL] {
        defer { urls.removeAll() }
        return urls
    }
}
