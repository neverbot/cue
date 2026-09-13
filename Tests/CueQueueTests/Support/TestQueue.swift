import CueCore
import CuePlayer
@testable import CueQueue
import Foundation

enum TestQueue {
    static let first = VideoID("dQw4w9WgXcQ")!
    static let second = VideoID("jNQXAC9IVRw")!
    /// An obviously synthetic id, for a row that needs no real video.
    static let third = VideoID("12345678-_a")!
    static let date = Date(timeIntervalSince1970: 1_800_000_000)

    static func store() throws -> QueueStore {
        QueueStore(database: try QueueDatabase.inMemory())
    }

    /// A directory under the system temporary directory; never the real Application Support.
    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "cue-queue-tests-\(UUID().uuidString)")
    }
}
