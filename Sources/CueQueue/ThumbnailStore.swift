import CueCore
import Foundation
import os

/// Which of YouTube's public still images to fetch. Sizes measured on a real video: 10 KB, 21 KB and 65 KB.
public enum ThumbnailQuality: String, Sendable, CaseIterable {
    /// 320×180.
    case medium
    /// 480×360.
    case high
    /// The original upload size, when the video has one.
    case max

    var remoteName: String {
        switch self {
        case .medium: "mqdefault.jpg"
        case .high: "hqdefault.jpg"
        case .max: "maxresdefault.jpg"
        }
    }

    var fileSuffix: String {
        switch self {
        case .medium: "mq"
        case .high: "hq"
        case .max: "max"
        }
    }
}

public enum ThumbnailError: Error, Equatable, Sendable {
    case httpStatus(Int)
    case empty
}

/// Fetches and caches sidebar thumbnails. The cache holds nothing but public still images named by video id: no
/// request metadata, no cookies, no stream URLs, nothing personal. It lives in the user's Caches directory, outside
/// the repository and outside Application Support, because the system may delete it at any time and everything in it
/// can be fetched again.
public actor ThumbnailStore {
    /// Total bytes the cache may hold before the oldest files are dropped.
    public static let defaultByteBudget = 32 * 1024 * 1024

    /// `~/Library/Caches/Cue/thumbnails`.
    public static var defaultDirectory: URL {
        URL.cachesDirectory
            .appending(path: "Cue", directoryHint: .isDirectory)
            .appending(path: "thumbnails", directoryHint: .isDirectory)
    }

    /// The public image URL for a video. No signature, no expiry, nothing that identifies the requester.
    public static func remoteURL(for videoID: VideoID, quality: ThumbnailQuality) -> URL {
        URL(string: "https://i.ytimg.com/vi/\(videoID.rawValue)/\(quality.remoteName)")!
    }

    private let directory: URL
    private let http: any HTTPClient
    private let quality: ThumbnailQuality
    private let byteBudget: Int
    private var failed: Set<VideoID> = []
    private let logger = Logger(subsystem: "com.neverbot.cue", category: "thumbnails")

    public init(
        directory: URL,
        http: any HTTPClient = URLSessionHTTPClient(session: URLSession(configuration: .ephemeral)),
        quality: ThumbnailQuality = .medium,
        byteBudget: Int = ThumbnailStore.defaultByteBudget
    ) {
        self.directory = directory
        self.http = http
        self.quality = quality
        self.byteBudget = byteBudget
    }

    public func fileURL(for videoID: VideoID) -> URL {
        directory.appending(path: "\(videoID.rawValue)-\(quality.fileSuffix).jpg", directoryHint: .notDirectory)
    }

    /// The cached image, without touching the network.
    public func cachedImageData(for videoID: VideoID) -> Data? {
        try? Data(contentsOf: fileURL(for: videoID))
    }

    /// The cached image, or a freshly fetched one. A video whose image cannot be fetched is remembered, so a queue of
    /// deleted videos does not retry on every redraw.
    public func imageData(for videoID: VideoID) async throws -> Data {
        if let cached = cachedImageData(for: videoID) { return cached }
        guard !failed.contains(videoID) else { throw ThumbnailError.empty }
        let url = Self.remoteURL(for: videoID, quality: quality)
        do {
            let response = try await http.send(HTTPRequest(url: url))
            guard response.status == 200 else { throw ThumbnailError.httpStatus(response.status) }
            guard !response.body.isEmpty else { throw ThumbnailError.empty }
            try store(response.body, for: videoID)
            return response.body
        } catch {
            failed.insert(videoID)
            throw error
        }
    }

    /// Total bytes currently cached.
    public func cachedByteCount() -> Int {
        contents().reduce(0) { $0 + $1.size }
    }

    /// Drops the least recently fetched files until the cache fits the budget.
    public func evictIfNeeded() {
        var files = contents()
        var total = files.reduce(0) { $0 + $1.size }
        guard total > byteBudget else { return }
        files.sort { $0.modified < $1.modified }
        for file in files where total > byteBudget {
            try? FileManager.default.removeItem(at: file.url)
            total -= file.size
        }
    }

    public func clear() {
        try? FileManager.default.removeItem(at: directory)
        failed.removeAll()
    }

    private func store(_ data: Data, for videoID: VideoID) throws {
        // The file names are the ids of videos the user queued, so the directory is created `rwx------`.
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: fileURL(for: videoID), options: .atomic)
        evictIfNeeded()
    }

    private func contents() -> [(url: URL, size: Int, modified: Date)] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return (url, values?.fileSize ?? 0, values?.contentModificationDate ?? .distantPast)
        }
    }
}
