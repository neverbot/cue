import Foundation
import Testing
@testable import CueCore

@Suite struct StoryboardStoreTests {
    let first = URL(string: "https://i.ytimg.com/sb/12345678-_a/storyboard3_L2/M0.jpg?sigh=rs$test")!
    let second = URL(string: "https://i.ytimg.com/sb/12345678-_a/storyboard3_L2/M1.jpg?sigh=rs$test")!

    func store(_ http: StubHTTPClient, limit: Int = 24) -> StoryboardStore {
        StoryboardStore(http: http, userAgent: "test-agent", sheetLimit: limit)
    }

    func stub(body: Data = Data([0xFF, 0xD8, 0xFF]), status: Int = 200) -> StubHTTPClient {
        let http = StubHTTPClient()
        http.on(pathSuffix: ".jpg", status: status, body: body)
        return http
    }

    @Test func fetchesASheetOnceAndKeepsIt() async throws {
        let http = stub()
        let store = store(http)

        let one = try await store.sheet(at: first)
        let two = try await store.sheet(at: first)

        #expect(one == two)
        #expect(http.recorded.count == 1)
    }

    /// A pointer sweeping the bar asks for the same sheet dozens of times before the first answer arrives.
    @Test func coalescesConcurrentRequestsForOneSheet() async throws {
        let http = stub()
        let store = store(http)

        try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<20 { group.addTask { try await store.sheet(at: self.first) } }
            for try await _ in group {}
        }

        #expect(http.recorded.count == 1)
    }

    @Test func fetchesDifferentSheetsSeparately() async throws {
        let http = stub()
        let store = store(http)

        _ = try await store.sheet(at: first)
        _ = try await store.sheet(at: second)

        #expect(http.recorded.count == 2)
    }

    @Test func sendsTheUserAgent() async throws {
        let http = stub()
        _ = try await store(http).sheet(at: first)
        #expect(http.recorded.first?.headers["User-Agent"] == "test-agent")
    }

    @Test func reportsAFailureAndRetriesTheNextTime() async throws {
        let http = stub(body: Data(), status: 403)
        let store = store(http)

        await #expect(throws: ExtractionError.self) { try await store.sheet(at: first) }
        await #expect(throws: ExtractionError.self) { try await store.sheet(at: first) }

        #expect(http.recorded.count == 2)
    }

    @Test func evictsTheLeastRecentlyUsedSheet() async throws {
        let http = stub()
        let store = store(http, limit: 1)

        _ = try await store.sheet(at: first)
        _ = try await store.sheet(at: second)
        _ = try await store.sheet(at: first)

        #expect(http.recorded.count == 3)
    }

    @Test func keepsEverythingUnderTheLimit() async throws {
        let http = stub()
        let store = store(http, limit: 2)

        _ = try await store.sheet(at: first)
        _ = try await store.sheet(at: second)
        _ = try await store.sheet(at: first)

        #expect(http.recorded.count == 2)
    }
}
