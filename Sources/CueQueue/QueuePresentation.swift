import CoreGraphics
import CueCore
import CuePlayer
import Foundation

/// How the sidebar draws its rows.
public enum QueueDisplayMode: String, CaseIterable, Sendable {
    /// Title, author and duration on two lines.
    case list
    /// A 16:9 thumbnail with the title beside it.
    case thumbnail
    /// One line per video, for long queues.
    case compact

    public var title: String {
        switch self {
        case .list: "List"
        case .thumbnail: "Thumbnails"
        case .compact: "Compact"
        }
    }

    public var rowHeight: CGFloat {
        switch self {
        case .list: 46
        case .thumbnail: 76
        case .compact: 24
        }
    }

    public var showsThumbnail: Bool { self == .thumbnail }

    /// The order the View menu and ⌃⌘M cycle through.
    public var next: QueueDisplayMode {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}

/// How the sidebar shares the window with the video.
public enum SidebarLayout: String, CaseIterable, Sendable {
    /// The video makes room for the sidebar.
    case push
    /// The sidebar floats over the video.
    case overlay

    public var title: String {
        switch self {
        case .push: "Push video"
        case .overlay: "Overlay video"
        }
    }
}

/// Which page the trailing inspector shows. The two are exclusive: the inspector is one column, not two.
public enum InspectorTab: String, CaseIterable, Sendable {
    /// The chapters of the video playing now.
    case chapters
    /// The caption tracks, their styling, their delay and their export.
    case subtitles

    public var title: String {
        switch self {
        case .chapters: "Chapters"
        case .subtitles: "Subtitles"
        }
    }
}

/// One sidebar row, ready to draw. The view layer adds no logic of its own.
public struct QueueRow: Equatable, Sendable {
    public var videoID: String
    public var title: String
    /// Author and duration, already joined; empty when neither is known.
    public var secondaryText: String
    public var durationText: String
    public var isWatched: Bool
    public var isCurrent: Bool
    public var showsThumbnail: Bool
    /// How far into the video the resume position is, 0–1, or nil when there is nothing to show.
    public var progress: Double?

    public init(
        videoID: String,
        title: String,
        secondaryText: String,
        durationText: String,
        isWatched: Bool,
        isCurrent: Bool,
        showsThumbnail: Bool,
        progress: Double?
    ) {
        self.videoID = videoID
        self.title = title
        self.secondaryText = secondaryText
        self.durationText = durationText
        self.isWatched = isWatched
        self.isCurrent = isCurrent
        self.showsThumbnail = showsThumbnail
        self.progress = progress
    }
}

/// Turns stored videos into rows and headers. Pure functions, so the sidebar's behaviour is testable without a window.
public enum QueuePresentation {
    public static func rows(for videos: [QueuedVideo], mode: QueueDisplayMode, current: VideoID? = nil) -> [QueueRow] {
        videos.map { video in
            QueueRow(
                videoID: video.videoID,
                title: video.title,
                secondaryText: secondaryText(for: video, mode: mode),
                durationText: video.duration.map(PlaybackTime.format) ?? "",
                isWatched: video.isWatched,
                isCurrent: video.videoID == current?.rawValue,
                showsThumbnail: mode.showsThumbnail,
                progress: progress(for: video)
            )
        }
    }

    /// The sidebar header: how many videos are left.
    public static func counterText(for summary: QueueSummary) -> String {
        guard summary.pendingCount > 0 else {
            return summary.watchedCount > 0 ? "Nothing left to watch" : "Queue empty"
        }
        return "\(summary.pendingCount) \(summary.pendingCount == 1 ? "video" : "videos")"
    }

    private static func secondaryText(for video: QueuedVideo, mode: QueueDisplayMode) -> String {
        var parts: [String] = []
        if let author = video.author, !author.isEmpty { parts.append(author) }
        if mode != .compact, let duration = video.duration { parts.append(PlaybackTime.format(duration)) }
        return parts.joined(separator: " · ")
    }

    private static func progress(for video: QueuedVideo) -> Double? {
        guard !video.isWatched, let duration = video.duration, duration > 0,
              let position = video.resumePosition, position > 0, position < duration
        else { return nil }
        return position / duration
    }
}
