import CueCore
@testable import CueQueue
import Foundation
import Testing

@Suite struct ThumbnailStoreTests {
    private func image(_ byteCount: Int) -> Data {
        Data(repeating: 0x42, count: byteCount)
    }

    @Test func buildsThePublicImageURLs() {
        #expect(ThumbnailStore.remoteURL(for: TestQueue.first, quality: .medium).absoluteString
            == "https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg")
        #expect(ThumbnailStore.remoteURL(for: TestQueue.first, quality: .high).absoluteString
            == "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
        #expect(ThumbnailStore.remoteURL(for: TestQueue.second, quality: .max).absoluteString
            == "https://i.ytimg.com/vi/jNQXAC9IVRw/maxresdefault.jpg")
    }

    @Test func fetchesOnceAndThenReadsFromDisk() async throws {
        let directory = TestQueue.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let http = FakeHTTPClient([HTTPResponse(status: 200, body: image(64))])
        let store = ThumbnailStore(directory: directory, http: http)

        let first = try await store.imageData(for: TestQueue.first)
        let second = try await store.imageData(for: TestQueue.first)

        #expect(first == image(64))
        #expect(second == image(64))
        #expect(http.requestedURLs.count == 1)
        #expect(await store.cachedImageData(for: TestQueue.first) == image(64))

        // The file names are the ids of videos the user queued, so the cache directory is created `rwx------`.
        let mode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int
        #expect(mode == 0o700)
    }

    @Test func hasNothingCachedBeforeAFetch() async {
        let store = ThumbnailStore(directory: TestQueue.temporaryDirectory(), http: FakeHTTPClient([]))
        #expect(await store.cachedImageData(for: TestQueue.first) == nil)
    }

    @Test func namesCacheFilesAfterTheVideoIdAndNothingElse() async {
        let directory = TestQueue.temporaryDirectory()
        let store = ThumbnailStore(directory: directory, http: FakeHTTPClient([]))

        let fileURL = await store.fileURL(for: TestQueue.first)
        #expect(fileURL.lastPathComponent == "dQw4w9WgXcQ-mq.jpg")
        #expect(fileURL.deletingLastPathComponent().path == directory.path)
    }

    @Test func reportsAFailureAndDoesNotAskAgain() async throws {
        let directory = TestQueue.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let http = FakeHTTPClient([HTTPResponse(status: 404, body: Data())])
        let store = ThumbnailStore(directory: directory, http: http)

        await #expect(throws: ThumbnailError.httpStatus(404)) { try await store.imageData(for: TestQueue.first) }
        await #expect(throws: ThumbnailError.empty) { try await store.imageData(for: TestQueue.first) }
        #expect(http.requestedURLs.count == 1)
    }

    @Test func refusesAnEmptyBody() async throws {
        let directory = TestQueue.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailStore(directory: directory, http: FakeHTTPClient([HTTPResponse(status: 200, body: Data())]))

        await #expect(throws: ThumbnailError.empty) { try await store.imageData(for: TestQueue.first) }
        #expect(await store.cachedImageData(for: TestQueue.first) == nil)
    }

    @Test func dropsTheOldestFilesOverTheBudget() async throws {
        let directory = TestQueue.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let http = FakeHTTPClient([
            HTTPResponse(status: 200, body: image(600)),
            HTTPResponse(status: 200, body: image(600)),
        ])
        let store = ThumbnailStore(directory: directory, http: http, byteBudget: 1000)

        _ = try await store.imageData(for: TestQueue.first)
        // Age the first file into the past, so the eviction order is not decided by two identical timestamps.
        // `TestQueue.date` would be wrong here: it is in the future, which would make this the newest file.
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)],
            ofItemAtPath: await store.fileURL(for: TestQueue.first).path
        )
        _ = try await store.imageData(for: TestQueue.second)

        #expect(await store.cachedByteCount() <= 1000)
        #expect(await store.cachedImageData(for: TestQueue.first) == nil)
        #expect(await store.cachedImageData(for: TestQueue.second) == image(600))
    }

    @Test func keepsEverythingThatFitsTheBudget() async throws {
        let directory = TestQueue.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let http = FakeHTTPClient([
            HTTPResponse(status: 200, body: image(100)),
            HTTPResponse(status: 200, body: image(100)),
        ])
        let store = ThumbnailStore(directory: directory, http: http, byteBudget: 1000)

        _ = try await store.imageData(for: TestQueue.first)
        _ = try await store.imageData(for: TestQueue.second)

        #expect(await store.cachedByteCount() == 200)
        #expect(await store.cachedImageData(for: TestQueue.first) != nil)
    }

    @Test func measuresAnEmptyStoreAsNothing() async {
        // Nothing has been fetched, so the directory does not exist yet. Measuring it is still a question with an
        // answer: zero, not a failure.
        let store = ThumbnailStore(directory: TestQueue.temporaryDirectory(), http: FakeHTTPClient([]))
        #expect(await store.cachedByteCount() == 0)
    }

    @Test func measuresWhatItHasStored() async throws {
        let directory = TestQueue.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let http = FakeHTTPClient([
            HTTPResponse(status: 200, body: image(64)),
            HTTPResponse(status: 200, body: image(150)),
        ])
        let store = ThumbnailStore(directory: directory, http: http)

        _ = try await store.imageData(for: TestQueue.first)
        #expect(await store.cachedByteCount() == 64)

        _ = try await store.imageData(for: TestQueue.second)
        #expect(await store.cachedByteCount() == 214)
    }

    @Test func emptiesTheCacheAndReportsWhatItFreed() async throws {
        let directory = TestQueue.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let http = FakeHTTPClient([
            HTTPResponse(status: 200, body: image(64)),
            HTTPResponse(status: 200, body: image(150)),
        ])
        let store = ThumbnailStore(directory: directory, http: http)
        _ = try await store.imageData(for: TestQueue.first)
        _ = try await store.imageData(for: TestQueue.second)

        #expect(await store.empty() == 214)
        #expect(await store.cachedByteCount() == 0)
        #expect(await store.cachedImageData(for: TestQueue.first) == nil)
    }

    @Test func freesNothingFromACacheThatHasNothingInIt() async {
        let store = ThumbnailStore(directory: TestQueue.temporaryDirectory(), http: FakeHTTPClient([]))
        #expect(await store.empty() == 0)
    }

    /// Unlike `clear()`, emptying leaves the directory where it is and fit to be written to again.
    @Test func leavesTheDirectoryUsableAfterEmptyingIt() async throws {
        let directory = TestQueue.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let http = FakeHTTPClient([
            HTTPResponse(status: 200, body: image(64)),
            HTTPResponse(status: 200, body: image(90)),
        ])
        let store = ThumbnailStore(directory: directory, http: http)
        _ = try await store.imageData(for: TestQueue.first)

        _ = await store.empty()

        #expect(FileManager.default.fileExists(atPath: directory.path))
        let fetched = try await store.imageData(for: TestQueue.second)
        #expect(fetched == image(90))
        #expect(await store.cachedByteCount() == 90)
    }

    /// A re-fetch goes back to the network for an image that is already on disk, which is the whole point of it, and
    /// forgets a previous failure so a video that was unreachable last time is tried once more.
    @Test func refetchesAnImageItAlreadyHas() async throws {
        let directory = TestQueue.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let http = FakeHTTPClient([
            HTTPResponse(status: 200, body: image(64)),
            HTTPResponse(status: 200, body: image(128)),
        ])
        let store = ThumbnailStore(directory: directory, http: http)
        _ = try await store.imageData(for: TestQueue.first)

        let refreshed = try await store.refreshedImageData(for: TestQueue.first)
        #expect(refreshed == image(128))
        #expect(http.requestedURLs.count == 2)
        #expect(await store.cachedImageData(for: TestQueue.first) == image(128))
    }

    @Test func triesAgainForAVideoWhoseImageFailedBefore() async throws {
        let directory = TestQueue.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let http = FakeHTTPClient([
            HTTPResponse(status: 404, body: Data()),
            HTTPResponse(status: 200, body: image(64)),
        ])
        let store = ThumbnailStore(directory: directory, http: http)
        await #expect(throws: ThumbnailError.httpStatus(404)) { try await store.imageData(for: TestQueue.first) }

        let retried = try await store.refreshedImageData(for: TestQueue.first)
        #expect(retried == image(64))
        #expect(http.requestedURLs.count == 2)
    }

    @Test func clearsTheWholeCache() async throws {
        let directory = TestQueue.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThumbnailStore(directory: directory, http: FakeHTTPClient([HTTPResponse(status: 200, body: image(64))]))
        _ = try await store.imageData(for: TestQueue.first)

        await store.clear()

        #expect(await store.cachedImageData(for: TestQueue.first) == nil)
        #expect(FileManager.default.fileExists(atPath: directory.path) == false)
    }
}
