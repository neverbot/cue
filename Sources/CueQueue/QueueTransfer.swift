import CueCore
import Foundation

/// The three interchange formats. `urlList` is the lowest common denominator, `json` is Cue's own and round-trips
/// everything, `csv` reads the shape Google Takeout exports for a playlist.
public enum QueueFormat: String, CaseIterable, Sendable {
    case urlList
    case json
    case csv

    public var fileExtension: String {
        switch self {
        case .urlList: "txt"
        case .json: "json"
        case .csv: "csv"
        }
    }

    public var title: String {
        switch self {
        case .urlList: "URL list"
        case .json: "Cue JSON"
        case .csv: "CSV"
        }
    }

    /// The format of a file, from its extension and then from its contents: JSON starts with a brace, a Takeout CSV
    /// has a header naming a video column, everything else is read as a URL list.
    public static func detect(fileExtension extensionName: String?, contents: String) -> QueueFormat {
        switch extensionName?.lowercased() {
        case "json": return .json
        case "csv": return .csv
        case "txt": return .urlList
        default: break
        }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") { return .json }
        if let header = trimmed.split(whereSeparator: \.isNewline).first,
           CSVQueueFormat.columnIndices(inHeader: CSVQueueFormat.fields(in: String(header))) != nil {
            return .csv
        }
        return .urlList
    }

    /// Like `detect`, but for a save panel's chosen URL: an extensionless name (the user cleared the field the
    /// suggested `.json` name filled in) must not silently fall back to the lossy URL list, so it defaults to
    /// `.json` instead.
    public static func detectForExport(fileExtension: String?) -> QueueFormat {
        guard let fileExtension, !fileExtension.isEmpty else { return .json }
        return detect(fileExtension: fileExtension, contents: "")
    }
}

/// One video an import found, before the store decides whether it is new.
public struct ImportCandidate: Equatable, Sendable {
    public var videoID: VideoID
    public var title: String?
    public var author: String?
    public var duration: Double?
    public var addedAt: Date?
    public var watchedAt: Date?

    public init(
        videoID: VideoID,
        title: String? = nil,
        author: String? = nil,
        duration: Double? = nil,
        addedAt: Date? = nil,
        watchedAt: Date? = nil
    ) {
        self.videoID = videoID
        self.title = title
        self.author = author
        self.duration = duration
        self.addedAt = addedAt
        self.watchedAt = watchedAt
    }
}

/// What an import did. `unreadable` keeps the lines that held no video so the app can show them: an import that
/// silently drops half a file is indistinguishable from a broken import.
public struct ImportReport: Equatable, Sendable {
    public var added: Int
    public var duplicates: Int
    public var unreadable: [String]

    public init(added: Int = 0, duplicates: Int = 0, unreadable: [String] = []) {
        self.added = added
        self.duplicates = duplicates
        self.unreadable = unreadable
    }

    /// A one-line summary for the app to show.
    public var summary: String {
        var parts = ["Added \(added) \(added == 1 ? "video" : "videos")"]
        if duplicates > 0 { parts.append("skipped \(duplicates) already queued") }
        if !unreadable.isEmpty { parts.append("ignored \(unreadable.count) unreadable \(unreadable.count == 1 ? "line" : "lines")") }
        return parts.joined(separator: ", ") + "."
    }
}

/// Reads the three formats into candidates, and applies candidates to a store.
public enum QueueImport {
    /// Cue's own JSON: `{"version": 1, "items": [...]}`.
    public static let jsonFormatVersion = 1

    private struct JSONDocument: Codable {
        var version: Int
        var items: [JSONItem]
    }

    private struct JSONItem: Codable {
        var videoID: String
        var title: String?
        var author: String?
        var duration: Double?
        var addedAt: Date?
        var watchedAt: Date?
    }

    public enum ImportError: Error, Equatable, Sendable {
        case unreadableJSON
        case unsupportedJSONVersion(Int)
    }

    /// Parses `contents` in `format`. Unreadable lines are returned, never dropped silently.
    public static func candidates(in contents: String, format: QueueFormat) throws -> (candidates: [ImportCandidate], unreadable: [String]) {
        switch format {
        case .urlList: return urlListCandidates(in: contents)
        case .csv: return CSVQueueFormat.candidates(in: contents)
        case .json: return try jsonCandidates(in: contents)
        }
    }

    /// Applies candidates in order. Adding is idempotent: a video already in the queue counts as a duplicate and is
    /// left exactly as it is, which is what makes re-importing the same file safe.
    public static func apply(
        _ candidates: [ImportCandidate],
        unreadable: [String] = [],
        to store: QueueStore,
        now: Date = Date()
    ) throws -> ImportReport {
        var report = ImportReport(unreadable: unreadable)
        for candidate in candidates {
            let added = try store.add(
                candidate.videoID,
                title: candidate.title,
                author: candidate.author,
                duration: candidate.duration,
                addedAt: candidate.addedAt ?? now
            )
            guard added else {
                report.duplicates += 1
                continue
            }
            report.added += 1
            if let watchedAt = candidate.watchedAt {
                try store.markWatched(candidate.videoID, at: watchedAt)
            }
        }
        return report
    }

    private static func urlListCandidates(in contents: String) -> ([ImportCandidate], [String]) {
        var candidates: [ImportCandidate] = []
        var unreadable: [String] = []
        var seen: Set<VideoID> = []
        for line in contents.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.isEmpty || text.hasPrefix("#") { continue }
            guard let videoID = VideoID(url: text) else {
                unreadable.append(text)
                continue
            }
            guard seen.insert(videoID).inserted else { continue }
            candidates.append(ImportCandidate(videoID: videoID))
        }
        return (candidates, unreadable)
    }

    private static func jsonCandidates(in contents: String) throws -> ([ImportCandidate], [String]) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let document = try? decoder.decode(JSONDocument.self, from: Data(contents.utf8)) else {
            throw ImportError.unreadableJSON
        }
        guard document.version == jsonFormatVersion else {
            throw ImportError.unsupportedJSONVersion(document.version)
        }
        var candidates: [ImportCandidate] = []
        var unreadable: [String] = []
        var seen: Set<VideoID> = []
        for item in document.items {
            guard let videoID = VideoID(item.videoID) ?? VideoID(url: item.videoID) else {
                unreadable.append(item.videoID)
                continue
            }
            guard seen.insert(videoID).inserted else { continue }
            candidates.append(ImportCandidate(
                videoID: videoID, title: item.title, author: item.author, duration: item.duration,
                addedAt: item.addedAt, watchedAt: item.watchedAt
            ))
        }
        return (candidates, unreadable)
    }
}

/// Writes the three formats.
public enum QueueExport {
    /// One watch URL per line; an empty queue writes an empty file rather than a lone newline. Every row is exported
    /// from its stored identifier, so nothing is dropped for failing today's validation.
    public static func urlList(_ videos: [QueuedVideo]) -> String {
        guard !videos.isEmpty else { return "" }
        return videos
            .map { AddRequest.watchURL(forStoredIdentifier: $0.videoID).absoluteString }
            .joined(separator: "\n") + "\n"
    }

    /// Cue's own format: everything the queue knows, ready to be imported again.
    public static func json(_ videos: [QueuedVideo]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let document = JSONExportDocument(
            version: QueueImport.jsonFormatVersion,
            items: videos.map {
                JSONExportDocument.Item(
                    addedAt: $0.addedAt, author: $0.author, duration: $0.duration,
                    title: $0.title, videoID: $0.videoID, watchedAt: $0.watchedAt
                )
            }
        )
        return String(decoding: try encoder.encode(document), as: UTF8.self) + "\n"
    }

    /// The CSV the importer reads back, with the Takeout-style header.
    public static func csv(_ videos: [QueuedVideo]) -> String {
        CSVQueueFormat.document(videos)
    }

    /// `cue-queue-2026-09-12.json` and friends: the date, never a title or an id, so the file name leaks nothing.
    public static func suggestedFileName(for format: QueueFormat, on date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let stamp = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return "cue-queue-\(stamp).\(format.fileExtension)"
    }

    private struct JSONExportDocument: Encodable {
        struct Item: Encodable {
            var addedAt: Date
            var author: String?
            var duration: Double?
            var title: String
            var videoID: String
            var watchedAt: Date?
        }

        var version: Int
        var items: [Item]
    }
}

/// The CSV dialect Cue reads and writes: comma separated, `"` quoted, with a header naming the columns.
///
/// Google Takeout exports a playlist as `Video ID,Playlist Video Creation Timestamp`. Cue accepts that header and its
/// own wider one, matching column names case-insensitively:
///
/// | Cue field | Accepted column names |
/// |---|---|
/// | video id or URL | `video id`, `videoid`, `id`, `video url`, `url`, `video` |
/// | title | `title`, `video title` |
/// | author | `author`, `channel`, `channel title` |
/// | duration (seconds) | `duration`, `duration seconds` |
/// | added | `playlist video creation timestamp`, `video creation timestamp`, `timestamp`, `added`, `added timestamp` |
/// | watched | `watched`, `watched timestamp` |
///
/// A file whose header names none of the video columns is read as a URL list instead.
public enum CSVQueueFormat {
    static let idColumns = ["video id", "videoid", "id", "video url", "url", "video"]
    static let titleColumns = ["title", "video title"]
    static let authorColumns = ["author", "channel", "channel title"]
    static let durationColumns = ["duration", "duration seconds"]
    static let addedColumns = ["playlist video creation timestamp", "video creation timestamp", "timestamp", "added", "added timestamp"]
    static let watchedColumns = ["watched", "watched timestamp"]

    static let header = "Video ID,Title,Author,Duration Seconds,Added Timestamp,Watched Timestamp"

    struct ColumnIndices {
        var id: Int
        var title: Int?
        var author: Int?
        var duration: Int?
        var added: Int?
        var watched: Int?
    }

    static func candidates(in contents: String) -> ([ImportCandidate], [String]) {
        var rows = contents.split(whereSeparator: \.isNewline).map(String.init)
        guard !rows.isEmpty else { return ([], []) }
        var indices = ColumnIndices(id: 0)
        if let headerIndices = columnIndices(inHeader: fields(in: rows[0])) {
            indices = headerIndices
            rows.removeFirst()
        }

        var candidates: [ImportCandidate] = []
        var unreadable: [String] = []
        var seen: Set<VideoID> = []
        for row in rows {
            let trimmed = row.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let values = fields(in: row)
            guard indices.id < values.count, let videoID = VideoID(url: values[indices.id]) else {
                unreadable.append(trimmed)
                continue
            }
            guard seen.insert(videoID).inserted else { continue }
            candidates.append(ImportCandidate(
                videoID: videoID,
                title: value(values, at: indices.title),
                author: value(values, at: indices.author),
                duration: value(values, at: indices.duration).flatMap(Double.init),
                addedAt: value(values, at: indices.added).flatMap(date(from:)),
                watchedAt: value(values, at: indices.watched).flatMap(date(from:))
            ))
        }
        return (candidates, unreadable)
    }

    static func document(_ videos: [QueuedVideo]) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = [header]
        for video in videos {
            lines.append([
                quoted(video.videoID),
                quoted(video.title),
                quoted(video.author ?? ""),
                video.duration.map { String(format: "%.0f", $0) } ?? "",
                quoted(formatter.string(from: video.addedAt)),
                quoted(video.watchedAt.map(formatter.string(from:)) ?? ""),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Nil when the header names no video column, which is how a URL list is told apart from a CSV.
    static func columnIndices(inHeader headerFields: [String]) -> ColumnIndices? {
        let names = headerFields.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let id = names.firstIndex(where: idColumns.contains) else { return nil }
        return ColumnIndices(
            id: id,
            title: names.firstIndex(where: titleColumns.contains),
            author: names.firstIndex(where: authorColumns.contains),
            duration: names.firstIndex(where: durationColumns.contains),
            added: names.firstIndex(where: addedColumns.contains),
            watched: names.firstIndex(where: watchedColumns.contains)
        )
    }

    /// Splits one row: commas separate fields, `"` quotes a field and `""` is a literal quote inside one.
    /// Unquoted fields are trimmed, because spreadsheets pad them; a quoted field is kept exactly as written, spaces
    /// included, because the quotes are what say the spaces are part of the value.
    static func fields(in row: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var quoted = false
        var wasQuoted = false
        let characters = Array(row)
        var index = 0

        func endField() {
            fields.append(wasQuoted ? current : current.trimmingCharacters(in: .whitespaces))
            current = ""
            wasQuoted = false
        }

        while index < characters.count {
            let character = characters[index]
            if quoted {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        current.append("\"")
                        index += 1
                    } else {
                        quoted = false
                    }
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                quoted = true
                wasQuoted = true
            } else if character == "," {
                endField()
            } else {
                current.append(character)
            }
            index += 1
        }
        endField()
        return fields
    }

    /// `fields(in:)` has already trimmed what should be trimmed, so this must not trim again: doing so would strip
    /// the spaces a quoted field deliberately kept. An empty field reads as no value.
    private static func value(_ values: [String], at index: Int?) -> String? {
        guard let index, index < values.count else { return nil }
        let text = values[index]
        return text.isEmpty ? nil : text
    }

    /// ISO 8601, with and without fractional seconds (Takeout writes both).
    private static func date(from text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

    private static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
