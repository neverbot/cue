import Foundation

/// What a queue row needs to know about a video it is not playing: its name, and who published it.
public struct VideoSummary: Equatable, Sendable {
    public let videoID: VideoID
    public let title: String
    public let author: String?

    public init(videoID: VideoID, title: String, author: String? = nil) {
        self.videoID = videoID
        self.title = title
        self.author = author
    }
}

public enum VideoSummaryError: Error, Equatable, Sendable {
    case httpStatus(Int)
    case unexpectedResponse
    /// A response that parsed but named nothing: a title that is empty or blank is not a title.
    case emptyTitle
}

extension VideoSummaryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .httpStatus(status): "YouTube returned HTTP \(status) for this video's details."
        case .unexpectedResponse: "YouTube returned details Cue could not read."
        case .emptyTitle: "YouTube reported no title for this video."
        }
    }
}

/// Something that can name a video. A protocol so the sidebar can be handed a stub in place of the network.
public protocol VideoSummarising: Sendable {
    func summary(for videoID: VideoID) async throws -> VideoSummary
}

/// Names a video through YouTube's own oEmbed endpoint.
///
/// The cheapest question YouTube answers about a video: one unauthenticated `GET`, no cookies, no visitor data, no
/// player script and no JavaScript to run, answered with a few hundred bytes of JSON. The `/player` path the
/// extractor uses would also give the duration, but it costs a watch-page fetch plus an InnerTube call and hands
/// back signed stream URLs for a video the owner has not chosen to play. Naming a row is not worth that, so the
/// duration stays unknown until the video is actually played and the extractor fills it in.
public struct OEmbedSummaries: VideoSummarising {
    private let http: any HTTPClient

    public init(http: any HTTPClient = URLSessionHTTPClient(session: URLSession(configuration: .ephemeral))) {
        self.http = http
    }

    /// `https://www.youtube.com/oembed?url=<watch URL>&format=json`. `URLComponents` escapes the nested watch URL.
    public static func url(for videoID: VideoID) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/oembed"
        components.queryItems = [
            URLQueryItem(name: "url", value: WatchPage.url(for: videoID).absoluteString),
            URLQueryItem(name: "format", value: "json"),
        ]
        // The components above always form a valid URL.
        return components.url!
    }

    private struct Payload: Decodable {
        var title: String?
        var author_name: String?
    }

    public func summary(for videoID: VideoID) async throws -> VideoSummary {
        let response = try await http.send(HTTPRequest(url: Self.url(for: videoID)))
        // A video that was deleted or made private answers 401 or 404 here, which is a permanent no: the caller
        // remembers the failure rather than asking again.
        guard response.status == 200 else { throw VideoSummaryError.httpStatus(response.status) }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: response.body) else {
            throw VideoSummaryError.unexpectedResponse
        }
        let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { throw VideoSummaryError.emptyTitle }
        let author = payload.author_name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return VideoSummary(videoID: videoID, title: title, author: (author?.isEmpty ?? true) ? nil : author)
    }
}
