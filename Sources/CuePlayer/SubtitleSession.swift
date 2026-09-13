import CueCore
import Foundation

/// What subtitle is loaded, how it is delayed and how it looks — and the commands that put mpv in that state.
///
/// Cue loads **one** external subtitle at a time, removing the previous one before adding the next. That is what makes
/// the track's id predictable: `sub-add` answers asynchronously and never tells the caller which id it got, but with
/// exactly one external track loaded it is always the first one.
public struct SubtitleSession: Equatable, Sendable {
    /// The id of the only external track Cue ever adds.
    public static let externalTrackID = 1

    public private(set) var selected: CaptionTrack?
    /// Seconds; negative means the subtitle appears earlier.
    public var delay: Double = 0
    public var style = SubtitleStyle()

    public init() {}

    /// Loads `file` as the only external subtitle and applies the current delay and style.
    public mutating func select(_ track: CaptionTrack, file: URL) -> [PlayerCommand] {
        var commands: [PlayerCommand] = selected == nil ? [] : [.removeSubtitles]
        selected = track
        commands.append(.addSubtitle(fileURL: file))
        commands.append(.selectSubtitle(id: Self.externalTrackID))
        commands.append(.setSubtitleDelay(seconds: delay))
        commands += style.commands
        return commands
    }

    /// Turns subtitles off. The delay and the style survive: they are the user's settings, not the track's.
    public mutating func disable() -> [PlayerCommand] {
        guard selected != nil else { return [] }
        selected = nil
        return [.selectSubtitle(id: nil), .removeSubtitles]
    }

    public mutating func setDelay(_ seconds: Double) -> [PlayerCommand] {
        delay = seconds
        return [.setSubtitleDelay(seconds: seconds)]
    }

    public mutating func apply(_ style: SubtitleStyle) -> [PlayerCommand] {
        self.style = style
        return style.commands
    }

    /// Where Cue keeps the subtitle files it hands to mpv: a private directory that the system may empty at any time,
    /// because everything in it can be downloaded again.
    public static func defaultDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "cue-subtitles", directoryHint: .isDirectory)
    }

    /// Writes the cues as WebVTT and returns the file. mpv could load the track's URL directly, but that URL is
    /// bound to the requester's address and expires with the streams, so a subtitle loaded that way dies mid-video.
    @discardableResult
    public static func write(cues: [CaptionCue], for track: CaptionTrack, videoID: VideoID, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        let file = directory.appending(path: "\(videoID.rawValue).\(track.fileNameStem).vtt", directoryHint: .notDirectory)
        try Data(SubtitleWriter.vtt(cues).utf8).write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return file
    }

    /// Removes everything written for this session. Called when the window closes.
    public static func removeFiles(in directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}
