import CueCore
@testable import CuePlayer
import Foundation
import Testing

@Suite struct ResumePolicyTests {
    let policy = ResumePolicy()

    @Test func keepsPositionsBetweenTheStartAndTheEnd() {
        #expect(!policy.isWorthKeeping(position: 9.9, duration: 213))
        #expect(policy.isWorthKeeping(position: 10, duration: 213))
        #expect(policy.isWorthKeeping(position: 192.9, duration: 213))
        #expect(!policy.isWorthKeeping(position: 193, duration: 213))
        #expect(policy.isWorthKeeping(position: 5000, duration: nil))
    }

    @Test func resumesOnlyWorthwhileEntries() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(policy.startPosition(for: ResumeEntry(position: 42, duration: 213, updatedAt: date)) == 42)
        #expect(policy.startPosition(for: ResumeEntry(position: 205, duration: 213, updatedAt: date)) == nil)
        #expect(policy.startPosition(for: nil) == nil)
    }
}

@MainActor
@Suite struct JSONResumeStoreTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "cue-resume-tests-\(UUID().uuidString)")
    var fileURL: URL { directory.appending(path: "Cue/resume-positions.json") }
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func persistsEntriesAcrossInstances() {
        defer { try? FileManager.default.removeItem(at: directory) }
        let entry = ResumeEntry(position: 42.5, duration: 213, updatedAt: date)
        JSONResumeStore(fileURL: fileURL).save(entry, for: TestStreams.videoID)

        #expect(JSONResumeStore(fileURL: fileURL).entry(for: TestStreams.videoID) == entry)
    }

    @Test func removesEntries() {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONResumeStore(fileURL: fileURL)
        store.save(ResumeEntry(position: 42, duration: 213, updatedAt: date), for: TestStreams.videoID)
        store.remove(TestStreams.videoID)

        #expect(JSONResumeStore(fileURL: fileURL).entry(for: TestStreams.videoID) == nil)
    }

    @Test func keepsOnlyTheNewestEntriesOverTheLimit() {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONResumeStore(fileURL: fileURL, limit: 1)
        store.save(ResumeEntry(position: 42, duration: 213, updatedAt: date), for: TestStreams.videoID)
        store.save(ResumeEntry(position: 11, duration: 19, updatedAt: date.addingTimeInterval(60)), for: TestStreams.otherVideoID)

        let reloaded = JSONResumeStore(fileURL: fileURL)
        #expect(reloaded.entry(for: TestStreams.videoID) == nil)
        #expect(reloaded.entry(for: TestStreams.otherVideoID)?.position == 11)
    }

    @Test func startsEmptyFromAnUnreadableFile() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)

        #expect(JSONResumeStore(fileURL: fileURL).entry(for: TestStreams.videoID) == nil)
    }

    @Test func ignoresAFileWithAnUnexpectedFormatVersion() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let futureFormat = """
        {"version": 999, "entries": {"\(TestStreams.videoID.rawValue)": \
        {"position": 42, "duration": 213, "updatedAt": "2027-01-15T08:00:00Z"}}}
        """
        try Data(futureFormat.utf8).write(to: fileURL)

        #expect(JSONResumeStore(fileURL: fileURL).entry(for: TestStreams.videoID) == nil)
    }

    @Test func writesAVersionedHumanReadableFile() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        JSONResumeStore(fileURL: fileURL).save(ResumeEntry(position: 42, duration: nil, updatedAt: date), for: TestStreams.videoID)

        let text = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(text.contains(#""version" : 1"#))
        #expect(text.contains(#""dQw4w9WgXcQ""#))
        #expect(text.contains(#""updatedAt" : "2027-01-15T08:00:00Z""#))
    }
}
