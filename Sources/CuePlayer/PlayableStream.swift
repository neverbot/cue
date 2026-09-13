import CueCore
import Foundation

/// Everything the player needs to start one video, independent of how it was found.
public struct PlayableStream: Equatable, Sendable {
    public enum Decoding: Equatable, Sendable {
        case hardware
        case software
    }

    /// Nil for local files, which have no resume position.
    public var videoID: VideoID?
    public var title: String
    /// Who published the video, when the source says. The queue stores it so its sidebar can show it for videos that
    /// arrived by paste, drop or link, not only for imported ones.
    public var author: String?
    public var videoURL: URL
    /// A separate audio stream (YouTube serves DASH video and audio apart).
    public var audioURL: URL?
    /// Display size announced by the source, used to size the window before playback starts.
    public var videoSize: VideoSize?
    public var duration: Double?
    public var userAgent: String?
    public var expiresAt: Date?
    public var decoding: Decoding
    /// The video's own sections, empty when it has none.
    public var chapters: [Chapter] = []
    /// Caption tracks offered for this video; fetched only when the user asks for one.
    public var captionTracks: [CaptionTrack] = []
    /// Seek-bar preview sheets, when YouTube offers them.
    public var storyboard: StoryboardSpec?

    public init(
        videoID: VideoID?,
        title: String,
        author: String? = nil,
        videoURL: URL,
        audioURL: URL? = nil,
        videoSize: VideoSize? = nil,
        duration: Double? = nil,
        userAgent: String? = nil,
        expiresAt: Date? = nil,
        decoding: Decoding = .hardware,
        chapters: [Chapter] = [],
        captionTracks: [CaptionTrack] = [],
        storyboard: StoryboardSpec? = nil
    ) {
        self.videoID = videoID
        self.title = title
        self.author = author
        self.videoURL = videoURL
        self.audioURL = audioURL
        self.videoSize = videoSize
        self.duration = duration
        self.userAgent = userAgent
        self.expiresAt = expiresAt
        self.decoding = decoding
        self.chapters = chapters
        self.captionTracks = captionTracks
        self.storyboard = storyboard
    }
}

extension PlayableStream {
    public init(resolution: Resolution) {
        let video = resolution.selection.video
        self.init(
            videoID: resolution.videoID,
            title: resolution.title,
            author: resolution.author,
            videoURL: video.url,
            audioURL: resolution.selection.audio.url,
            videoSize: VideoSize(reportedWidth: video.width, reportedHeight: video.height),
            duration: resolution.duration,
            userAgent: resolution.userAgent,
            expiresAt: resolution.expiresAt,
            decoding: resolution.selection.decoding == .software ? .software : .hardware,
            chapters: resolution.chapters,
            captionTracks: resolution.captionTracks,
            storyboard: resolution.storyboard
        )
    }

    /// A local media file, for manual checks without network access.
    public init(fileURL: URL) {
        self.init(videoID: nil, title: fileURL.lastPathComponent, videoURL: fileURL)
    }
}

/// Resolves a video id into a stream at play time. `Extractor` is the production implementation.
public protocol StreamResolving: Sendable {
    func stream(for videoID: VideoID) async throws -> PlayableStream
}

extension Extractor: StreamResolving {
    public func stream(for videoID: VideoID) async throws -> PlayableStream {
        PlayableStream(resolution: try await resolve(videoID))
    }
}
