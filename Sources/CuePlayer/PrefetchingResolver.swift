import CueCore
import Foundation
import os

/// Warms a video's stream ahead of playback. `PrefetchingResolver` is the production implementation;
/// `QueueCoordinator` calls it, once a video starts, for the item that would play next.
public protocol StreamPrefetching: Sendable {
    /// Returns the background task doing the resolve, so tests can wait on it; production callers ignore it.
    @discardableResult
    func prefetch(_ videoID: VideoID) async -> Task<Void, Never>?
}

/// Decorates a `StreamResolving` with a small, bounded cache so the queue can resolve the next video ahead of time
/// and pay no extra latency when it is actually played. `PlayerController` keeps calling `stream(for:)` exactly as
/// before; it never needs to know a prefetch happened.
///
/// A cached entry is served only while it is fresh: `StreamFreshness.needsRefresh` (the same margin
/// `PlayerController` uses before a seek or resume) decides whether a resolved stream is still usable, so a
/// consumer never receives something staler than a freshly-resolved stream would be treated as. Every prefetch is
/// a real request to YouTube, so the cache holds at most `capacity` entries: eviction is preferred over unbounded
/// speculative resolving.
public actor PrefetchingResolver: StreamResolving, StreamPrefetching {
    /// At most this many videos are kept warm (in flight or resolved) at once.
    public static let capacity = 2

    private enum Entry {
        case inFlight(Task<PlayableStream, Error>)
        case ready(PlayableStream)
    }

    private let wrapped: StreamResolving
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: "com.neverbot.cue", category: "prefetch")
    private var cache: [VideoID: Entry] = [:]
    /// Insertion order, oldest first, so capacity eviction drops the entry that has waited longest.
    private var order: [VideoID] = []

    public init(wrapping resolver: StreamResolving, now: @escaping @Sendable () -> Date = { Date() }) {
        self.wrapped = resolver
        self.now = now
    }

    /// Resolves `videoID`, joining an in-flight prefetch or serving a fresh cached one instead of starting a
    /// second resolve. Falls through to the wrapped resolver, as if there were no cache at all, whenever no usable
    /// entry exists — so a failure here surfaces to the caller exactly as it would without prefetching.
    public func stream(for videoID: VideoID) async throws -> PlayableStream {
        switch cache[videoID] {
        case let .inFlight(task):
            return try await task.value
        case let .ready(stream):
            remove(videoID)
            if !StreamFreshness.needsRefresh(expiresAt: stream.expiresAt, now: now()) {
                return stream
            }
        case nil:
            break
        }
        let task = startResolve(videoID)
        do {
            let stream = try await task.value
            finish(videoID, with: .success(stream))
            return stream
        } catch {
            finish(videoID, with: .failure(error))
            throw error
        }
    }

    /// Speculatively resolves `videoID` and caches the result. Does nothing when a usable entry (in flight, or
    /// resolved and still fresh) already exists for it. Failures are swallowed — this is speculation, and the next
    /// real `stream(for:)` call resolves normally — and never logged with anything more than a redacted message.
    /// Returns the background task for tests to wait on; production callers can ignore it.
    @discardableResult
    public func prefetch(_ videoID: VideoID) -> Task<Void, Never>? {
        switch cache[videoID] {
        case .inFlight:
            return nil
        case let .ready(stream):
            guard StreamFreshness.needsRefresh(expiresAt: stream.expiresAt, now: now()) else { return nil }
        case nil:
            break
        }
        let task = startResolve(videoID)
        return Task { [self] in
            do {
                let stream = try await task.value
                finish(videoID, with: .success(stream))
            } catch {
                finish(videoID, with: .failure(error))
                logger.debug("Prefetch failed for \(videoID.rawValue, privacy: .private): \(LogRedactor.redact(String(describing: error)), privacy: .private)")
            }
        }
    }

    /// Creates the resolve task and registers it as in flight before returning, so the cache reflects it
    /// immediately: nothing can observe a gap where this video looks uncached while a resolve for it is starting.
    private func startResolve(_ videoID: VideoID) -> Task<PlayableStream, Error> {
        let task = Task<PlayableStream, Error> { [wrapped] in try await wrapped.stream(for: videoID) }
        insert(.inFlight(task), for: videoID)
        return task
    }

    /// Applies a settled result to the cache, but only while this video's entry is still the in-flight task that
    /// produced it — it may already have been evicted for capacity, or (for a prefetch) consumed by a real request
    /// that removed the ready entry it left behind.
    private func finish(_ videoID: VideoID, with result: Result<PlayableStream, Error>) {
        guard case .inFlight = cache[videoID] else { return }
        switch result {
        case let .success(stream): insert(.ready(stream), for: videoID)
        case .failure: remove(videoID)
        }
    }

    private func insert(_ entry: Entry, for videoID: VideoID) {
        cache[videoID] = entry
        order.removeAll { $0 == videoID }
        order.append(videoID)
        while order.count > Self.capacity {
            let evicted = order.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }

    private func remove(_ videoID: VideoID) {
        cache.removeValue(forKey: videoID)
        order.removeAll { $0 == videoID }
    }
}
