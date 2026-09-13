import CueCore
@testable import CuePlayer
import Foundation
import Testing

/// A mutable "now" a plain (non-`@MainActor`) actor test can call synchronously, mirroring the `@unchecked Sendable`
/// + lock convention `FakeResolver` already uses.
private final class MutableNow: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ date: Date) { current = date }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }

    var callback: @Sendable () -> Date { { [self] in lock.withLock { current } } }
}

@Suite struct PrefetchingResolverTests {
    let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func prefetchedVideoIsServedWithoutASecondResolve() async throws {
        let resolver = FakeResolver([.success(TestStreams.stream())])
        let prefetcher = PrefetchingResolver(wrapping: resolver)

        await prefetcher.prefetch(TestStreams.videoID)?.value
        let stream = try await prefetcher.stream(for: TestStreams.videoID)

        #expect(stream == TestStreams.stream())
        #expect(resolver.requests == [TestStreams.videoID])
    }

    @Test func nonPrefetchedVideoStillResolvesNormally() async throws {
        let resolver = FakeResolver([.success(TestStreams.stream())])
        let prefetcher = PrefetchingResolver(wrapping: resolver)

        let stream = try await prefetcher.stream(for: TestStreams.videoID)

        #expect(stream == TestStreams.stream())
        #expect(resolver.requests == [TestStreams.videoID])
    }

    @Test func expiredCacheEntryIsDiscardedAndReResolved() async throws {
        let now = MutableNow(baseDate)
        // Expires just past the safety margin from "now": fresh at prefetch time, stale by the time it is served.
        let expiresAt = baseDate.addingTimeInterval(StreamFreshness.safetyMargin + 10)
        let resolver = FakeResolver([
            .success(TestStreams.stream(expiresAt: expiresAt)),
            .success(TestStreams.stream()),
        ])
        let prefetcher = PrefetchingResolver(wrapping: resolver, now: now.callback)

        await prefetcher.prefetch(TestStreams.videoID)?.value
        now.advance(by: 11) // now + margin >= expiresAt
        let stream = try await prefetcher.stream(for: TestStreams.videoID)

        #expect(stream == TestStreams.stream())
        #expect(resolver.requests == [TestStreams.videoID, TestStreams.videoID])
    }

    @Test func aFreshCacheEntryIsNotReResolved() async throws {
        let now = MutableNow(baseDate)
        let expiresAt = baseDate.addingTimeInterval(StreamFreshness.safetyMargin + 1000)
        let stream = TestStreams.stream(expiresAt: expiresAt)
        let resolver = FakeResolver([.success(stream)])
        let prefetcher = PrefetchingResolver(wrapping: resolver, now: now.callback)

        await prefetcher.prefetch(TestStreams.videoID)?.value
        let served = try await prefetcher.stream(for: TestStreams.videoID)

        #expect(served == stream)
        #expect(resolver.requests == [TestStreams.videoID])
    }

    @Test func aFailingPrefetchDoesNotSurfaceAndDoesNotPoisonTheCache() async throws {
        let resolver = FakeResolver([
            .failure(ExtractionError.noPlayableFormats),
            .success(TestStreams.stream()),
        ])
        let prefetcher = PrefetchingResolver(wrapping: resolver)

        await prefetcher.prefetch(TestStreams.videoID)?.value // swallowed, must not throw
        let stream = try await prefetcher.stream(for: TestStreams.videoID)

        #expect(stream == TestStreams.stream())
        #expect(resolver.requests == [TestStreams.videoID, TestStreams.videoID])
    }

    @Test func theCacheStaysBounded() async throws {
        let ids = (0 ..< (PrefetchingResolver.capacity + 3)).map { index in
            VideoID(String(format: "1234567%03d_", index))!
        }
        // An extra result for `ids[0]`: it gets evicted once the cache fills, so it is resolved for real again below.
        let resolver = FakeResolver(ids.map { .success(TestStreams.stream(for: $0)) } + [.success(TestStreams.stream(for: ids[0]))])
        let prefetcher = PrefetchingResolver(wrapping: resolver)

        for id in ids {
            await prefetcher.prefetch(id)?.value
        }
        // Every prefetched id resolved without error and the cache never grew past `capacity`; the oldest ones
        // were evicted, so requesting one of them again resolves for real instead of erroring or hanging.
        _ = try await prefetcher.stream(for: ids[0])

        #expect(resolver.requests.filter { $0 == ids[0] }.count == 2)
    }

    @Test func aRealRequestJoinsAnInFlightPrefetch() async throws {
        let resolver = FakeResolver([.success(TestStreams.stream())], delays: [TestStreams.videoID: .milliseconds(50)])
        let prefetcher = PrefetchingResolver(wrapping: resolver)

        // `prefetch` registers the in-flight task synchronously before this call returns, so the following real
        // request is guaranteed to see it and join rather than racing a second resolve.
        let backgroundTask = await prefetcher.prefetch(TestStreams.videoID)
        let stream = try await prefetcher.stream(for: TestStreams.videoID)
        await backgroundTask?.value

        #expect(stream == TestStreams.stream())
        #expect(resolver.requests == [TestStreams.videoID])
    }
}
