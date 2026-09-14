import Foundation

/// The words the settings window uses about the thumbnail cache. Kept here, beside the other presentation helpers,
/// so what the app says about the cache can be tested without a window.
///
/// Counts and byte totals only. Nothing here takes a video id, a title or a path: the cache is named after the videos
/// in the owner's own queue, and a settings window ends up in screenshots.
public enum CachePresentation {
    /// What the size row shows while the directory is still being measured. The walk happens away from the main
    /// thread, so there is a moment with no answer, and a blank row in that moment reads as a broken one.
    public static let measuringText = "Measuring…"

    /// What the size row says. An empty cache says so in words rather than showing a formatted zero: nothing on disk
    /// is a state, not a measurement.
    public static func sizeText(bytes: Int) -> String {
        bytes > 0 ? formatted(bytes) : "Empty"
    }

    /// The whole report for emptying the cache. No sheet asks first — the images cost nothing to lose and come back
    /// on their own — so this one line is all that is said about it.
    public static func freedText(bytes: Int) -> String {
        bytes > 0 ? "Freed \(formatted(bytes))." : "The cache was already empty."
    }

    /// Progress through a re-fetch. The count is exact rather than estimated because the fetch is sequential: one
    /// request is awaited to the end before the next one starts.
    public static func progressText(completed: Int, total: Int) -> String {
        "\(max(completed, 0)) of \(max(total, 0))"
    }

    /// What a re-fetch says once it stops, whether it ran out of videos or was cancelled. A cancelled run reports how
    /// far it had got: it did real work, and pretending otherwise would misdescribe what is now on disk.
    public static func refetchedText(completed: Int, total: Int, cancelled: Bool) -> String {
        let done = max(completed, 0)
        guard !cancelled else { return "Stopped after \(done) of \(max(total, 0))." }
        return done == 1 ? "Fetched 1 thumbnail." : "Fetched \(done) thumbnails."
    }

    /// `ByteCountFormatter` in the file style, which is what the Finder shows and therefore what a size on screen is
    /// expected to agree with. Built per call rather than kept around: the formatter is not `Sendable`, and formatting
    /// a handful of labels costs nothing worth holding shared state for.
    private static func formatted(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        // "Zero KB" is never what this shows: nothing cached is reported in words by `sizeText(bytes:)` instead.
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(max(bytes, 0)))
    }
}
