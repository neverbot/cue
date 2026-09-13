import Foundation

/// Fetches storyboard sheets and keeps a few of them in memory.
///
/// An actor because a hover asks for the same sheet from many places at once: the in-flight table is what turns a
/// sweep across the seek bar into one request per sheet. Nothing is written to disk — a sheet is 30–60 KB, a video
/// needs two or three, and they are worthless once the video is done.
public actor StoryboardStore {
    private let http: any HTTPClient
    private let userAgent: String
    private let sheetLimit: Int
    private var sheets: [URL: Data] = [:]
    /// Most recently used last.
    private var order: [URL] = []
    private var inFlight: [URL: Task<Data, any Error>] = [:]

    public init(
        http: any HTTPClient = URLSessionHTTPClient(session: URLSession(configuration: .ephemeral)),
        userAgent: String,
        sheetLimit: Int = 24
    ) {
        self.http = http
        self.userAgent = userAgent
        self.sheetLimit = max(1, sheetLimit)
    }

    /// The sheet's bytes, fetched at most once while one fetch is in flight. A failure is not cached: the next hover
    /// tries again.
    public func sheet(at url: URL) async throws -> Data {
        if let cached = sheets[url] {
            touch(url)
            return cached
        }
        if let running = inFlight[url] {
            return try await running.value
        }
        let task = Task { [http, userAgent] in
            let response = try await http.send(HTTPRequest(url: url, headers: ["User-Agent": userAgent]))
            // A storyboard URL's query carries its `sigh` signature, and `ExtractionError.httpStatus` prints the
            // URL it is given. Hand it the endpoint alone, so a failure can be logged or shown without leaking it.
            guard response.status == 200 else { throw ExtractionError.httpStatus(response.status, Self.endpoint(of: url)) }
            guard !response.body.isEmpty else { throw ExtractionError.unexpectedResponse }
            return response.body
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        let data = try await task.value
        store(data, for: url)
        return data
    }

    /// Forgets everything. Called when the player opens another video.
    public func reset() {
        sheets.removeAll()
        order.removeAll()
    }

    private func store(_ data: Data, for url: URL) {
        sheets[url] = data
        touch(url)
        while order.count > sheetLimit, let oldest = order.first {
            order.removeFirst()
            sheets[oldest] = nil
        }
    }

    private func touch(_ url: URL) {
        order.removeAll { $0 == url }
        order.append(url)
    }

    /// The URL without its query: enough to say which request failed, with nothing secret in it.
    private static func endpoint(of url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.query = nil
        return components.url ?? url
    }
}
