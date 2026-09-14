import AppKit

/// Reads a drag as a file, for the two halves of the window that accept one: the queue sidebar and the picture.
///
/// Nothing here logs, copies or remembers the file. The list a user drops on Cue is their own, and the only thing the
/// app ever keeps of it is the video ids it decided to queue.
@MainActor
enum DroppedFile {
    /// The one file in a drag, or nil for anything else: a link, text, a row being reordered, or several files at
    /// once, which are refused rather than half read.
    static func url(in info: any NSDraggingInfo) -> URL? {
        let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        guard let urls, urls.count == 1 else { return nil }
        return urls[0]
    }
}
