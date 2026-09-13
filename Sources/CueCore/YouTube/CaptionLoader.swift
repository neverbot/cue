import Foundation

/// Downloads one caption track. Separate from `Extractor` because captions are fetched when the user asks for them,
/// not when a video is resolved: most videos are watched without ever opening the subtitles panel.
public struct CaptionLoader: Sendable {
    let http: any HTTPClient

    public init(http: any HTTPClient = URLSessionHTTPClient(session: URLSession(configuration: .ephemeral))) {
        self.http = http
    }

    /// The track's cues. `userAgent` must be the one the streams were resolved with.
    ///
    /// An empty body is an error, not an empty track: it is what YouTube answers when the URL came from somewhere
    /// other than the `/player` response that Cue itself requested.
    public func cues(for track: CaptionTrack, userAgent: String) async throws -> [CaptionCue] {
        let url = track.url(format: .json3)
        let response = try await http.send(HTTPRequest(url: url, headers: ["User-Agent": userAgent]))
        // A timed-text URL's query carries its signature, and `ExtractionError.httpStatus` prints the URL it is
        // given. Hand it the endpoint alone, so a failure can be logged or shown without leaking the signature.
        guard response.status == 200 else { throw ExtractionError.httpStatus(response.status, Self.endpoint(of: url)) }
        guard !response.body.isEmpty else { throw ExtractionError.unexpectedResponse }
        return try TimedText.cues(fromJSON3: response.body)
    }

    /// The URL without its query: enough to say which request failed, with nothing secret in it.
    static func endpoint(of url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.query = nil
        return components.url ?? url
    }
}
