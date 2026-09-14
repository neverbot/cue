import CueQueue
import Foundation

/// A file read and parsed, before anything has been added to the queue.
struct ParsedImportFile: Sendable {
    var format: QueueFormat
    var candidates: [ImportCandidate]
    var unreadable: [String]
}

/// Why a file never became an import. Every case says what happened without naming the file: the path of a personal
/// watch list is as private as its contents, and an alert ends up in screenshots.
enum ImportFileError: LocalizedError {
    case tooLarge(megabytes: Int)
    case notText
    case unreadable

    var errorDescription: String? {
        switch self {
        case let .tooLarge(megabytes):
            "That file is larger than \(megabytes) MB, far more than a list of links, so Cue did not read it."
        case .notText:
            "That file is not text Cue can read. A URL list, a Cue JSON file or a CSV export works."
        case .unreadable:
            "Cue could not read that file. It may have been moved, or Cue may not be allowed to open it."
        }
    }
}

/// Reads an import file off the main thread. Deliberately not part of the window controller: the window is on the main
/// actor and this work must not be, or a long list would freeze the picture while it is parsed.
///
/// Nothing here logs. Neither the path nor a single line of the file reaches the log, at any privacy level, because
/// the file is the user's own watch list and Cue's promise is that it stays on this machine and in this queue.
enum ImportFileReader {
    /// Well past any hand-kept list — a plain list of links runs to tens of kilobytes. A file over this is refused
    /// with a sentence rather than read: the alternative is a window that hangs, or a silent truncation that imports
    /// half a list and says it imported a list.
    static let sizeLimit = 8 * 1024 * 1024

    static var sizeLimitInMegabytes: Int { sizeLimit / (1024 * 1024) }

    /// Reads, detects the format and parses, all away from the main actor.
    static func read(_ url: URL) async throws -> ParsedImportFile {
        try await Task.detached(priority: .userInitiated) {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > sizeLimit {
                throw ImportFileError.tooLarge(megabytes: sizeLimitInMegabytes)
            }
            guard let data = try? Data(contentsOf: url) else { throw ImportFileError.unreadable }
            // Checked again on the bytes actually read: the size above is what the file system claimed a moment ago,
            // and a file being written to can outgrow it between the two.
            guard data.count <= sizeLimit else { throw ImportFileError.tooLarge(megabytes: sizeLimitInMegabytes) }
            guard let contents = String(data: data, encoding: .utf8) else { throw ImportFileError.notText }
            let format = QueueFormat.detect(fileExtension: url.pathExtension, contents: contents)
            let parsed = try QueueImport.candidates(in: contents, format: format)
            return ParsedImportFile(format: format, candidates: parsed.candidates, unreadable: parsed.unreadable)
        }.value
    }
}
