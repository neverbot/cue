import Foundation
import Testing
@testable import CueCore

/// Records the last request `URLSessionHTTPClient` sent through it and answers with a canned response.
private final class RequestRecorder: @unchecked Sendable {
    struct Recorded {
        let method: String
        let headers: [String: String]
        let body: Data?
    }

    private let lock = NSLock()
    private var _recorded: Recorded?

    var recorded: Recorded? {
        lock.lock()
        defer { lock.unlock() }
        return _recorded
    }

    func record(_ recorded: Recorded) {
        lock.lock()
        defer { lock.unlock() }
        _recorded = recorded
    }
}

private let recorder = RequestRecorder()

private final class StubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let headers = request.allHTTPHeaderFields ?? [:]
        let body = requestBody()
        recorder.record(RequestRecorder.Recorded(method: request.httpMethod ?? "GET", headers: headers, body: body))

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com/")!,
            statusCode: 201,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("ok".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func requestBody() -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }
}

@Suite(.serialized)
struct URLSessionHTTPClientTests {
    private func makeClient() -> URLSessionHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSessionHTTPClient(session: URLSession(configuration: configuration))
    }

    @Test func forwardsMethodHeadersAndBody() async throws {
        let client = makeClient()
        let body = Data(#"{"a":1}"#.utf8)
        let request = HTTPRequest(
            url: URL(string: "https://example.com/echo")!,
            method: "POST",
            headers: ["X-Test": "1", "Content-Type": "application/json"],
            body: body
        )

        let response = try await client.send(request)

        let recorded = try #require(recorder.recorded)
        #expect(recorded.method == "POST")
        #expect(recorded.headers["X-Test"] == "1")
        #expect(recorded.body == body)
        #expect(response.status == 201)
        #expect(response.body == Data("ok".utf8))
    }

    @Test func defaultsToGet() async throws {
        let client = makeClient()
        let request = HTTPRequest(url: URL(string: "https://example.com/plain")!)

        _ = try await client.send(request)

        let recorded = try #require(recorder.recorded)
        #expect(recorded.method == "GET")
        #expect(recorded.body == nil)
    }
}
