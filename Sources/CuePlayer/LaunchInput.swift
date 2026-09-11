import CueCore
import Foundation

/// What to open at launch or on paste, before the queue exists.
public enum LaunchInput: Equatable, Sendable {
    case video(VideoID)
    case file(URL)

    /// Cue's own `--` flags that take a value; every other `--` flag stands alone.
    public static let flagsWithValues: Set<String> = ["--smoke-test"]

    /// Parses command-line arguments (without the executable path). `--file <path>` opens a local media file.
    /// Skipped: Cue's other `--` flags, `-psn_…` process serial numbers and AppKit's `-Key value` user-default
    /// overrides such as `-ApplePersistenceIgnoreState YES`.
    public static func parse(arguments: [String]) -> LaunchInput? {
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            if argument == "--file", let path = remaining.popFirst() {
                return .file(URL(fileURLWithPath: path))
            }
            // A bare video id is checked first: ids may start with "-", which would otherwise look like an option.
            if let videoID = VideoID(argument) { return .video(videoID) }
            if argument.hasPrefix("--") {
                if flagsWithValues.contains(argument) { _ = remaining.popFirst() }
                continue
            }
            if argument.hasPrefix("-psn_") { continue }
            if argument.hasPrefix("-") {
                _ = remaining.popFirst()
                continue
            }
            if let videoID = VideoID(url: argument) { return .video(videoID) }
        }
        return nil
    }

    /// Parses pasted text: the first line that is a YouTube URL or video id.
    public static func parse(pastedText text: String?) -> LaunchInput? {
        guard let text else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            if let videoID = VideoID(url: String(line)) { return .video(videoID) }
        }
        return nil
    }
}
