import Foundation

/// What to say before an import that has not happened yet: a dropped file is read and counted first, and the queue is
/// only changed once the answer comes back.
public struct QueueImportPrompt: Equatable, Sendable {
    /// The headline: how many videos the file holds, or that it holds none.
    public var message: String
    /// The line under it, when there is something more to admit — entries that could not be read, or the fact that
    /// nothing was added. Nil when the headline already says everything.
    public var detail: String?
    /// Whether adding is on offer at all. False when the file held nothing to add, so the sheet acknowledges the file
    /// instead of asking a question with no answer.
    public var canAdd: Bool

    public init(message: String, detail: String? = nil, canAdd: Bool) {
        self.message = message
        self.detail = detail
        self.canAdd = canAdd
    }
}

/// The words a pending import uses. Kept out of the view layer so what the app says about a file can be tested without
/// a window — and so a file the user dropped never has to be opened again to find out.
public enum QueueImportPresentation {
    /// The prompt for a file that yielded `candidates` videos and `unreadable` entries that held none.
    ///
    /// Counts only: nothing here takes a line of the file, a title or a path, because the file being described is the
    /// user's own list and the sheet ends up in screenshots.
    public static func prompt(candidates: Int, unreadable: Int) -> QueueImportPrompt {
        let found = max(candidates, 0)
        let ignored = max(unreadable, 0)
        guard found > 0 else {
            return QueueImportPrompt(
                message: "That file has no YouTube links.",
                detail: ignored > 0
                    ? "\(ignored) \(ignored == 1 ? "line" : "lines") could not be read as a YouTube link. Nothing was added to the queue."
                    : "Nothing was added to the queue.",
                canAdd: false
            )
        }
        let message = found == 1
            ? "Found 1 YouTube link. Add it?"
            : "Found \(found) YouTube links. Add them all?"
        let detail = ignored > 0
            ? "\(ignored) other \(ignored == 1 ? "line" : "lines") could not be read as a YouTube link and will be ignored."
            : nil
        return QueueImportPrompt(message: message, detail: detail, canAdd: true)
    }
}
