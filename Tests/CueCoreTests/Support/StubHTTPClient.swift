import Foundation
@testable import CueCore

/// Offline HTTP client: first matching route wins; every request is recorded.
final class StubHTTPClient: HTTPClient, @unchecked Sendable {
    enum StubError: Error { case unrouted(URL) }

    private let lock = NSLock()
    private var routes: [(matches: (HTTPRequest) -> Bool, response: HTTPResponse)] = []
    private var requests: [HTTPRequest] = []

    var recorded: [HTTPRequest] { lock.withLock { requests } }

    func on(path: String, status: Int = 200, body: Data) {
        lock.withLock { routes.append(({ $0.url.path == path }, HTTPResponse(status: status, body: body))) }
    }

    func on(pathSuffix: String, status: Int = 200, body: Data) {
        lock.withLock { routes.append(({ $0.url.path.hasSuffix(pathSuffix) }, HTTPResponse(status: status, body: body))) }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try lock.withLock {
            requests.append(request)
            guard let route = routes.first(where: { $0.matches(request) }) else { throw StubError.unrouted(request.url) }
            return route.response
        }
    }
}
