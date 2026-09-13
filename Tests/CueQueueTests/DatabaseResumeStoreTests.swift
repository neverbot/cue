import CueCore
import CuePlayer
@testable import CueQueue
import Foundation
import Testing

@MainActor
@Suite struct DatabaseResumeStoreTests {
    @Test func savesReadsAndRemovesPositions() throws {
        let store = try TestQueue.store()
        let resumeStore = DatabaseResumeStore(store: store)
        let entry = ResumeEntry(position: 42.5, duration: 213, updatedAt: TestQueue.date)

        resumeStore.save(entry, for: TestQueue.first)
        #expect(resumeStore.entry(for: TestQueue.first) == entry)

        resumeStore.remove(TestQueue.first)
        #expect(resumeStore.entry(for: TestQueue.first) == nil)
    }

    @Test func hasNoEntryForAnUnknownVideo() throws {
        let resumeStore = DatabaseResumeStore(store: try TestQueue.store())
        #expect(resumeStore.entry(for: TestQueue.second) == nil)
    }
}

@MainActor
@Suite struct JSONResumeImportTests {
    /// Writes a real file with the player's own JSON store, so the import stays compatible with what it produced.
    private func writeJSONFile(in directory: URL, entries: [(VideoID, ResumeEntry)]) -> URL {
        let fileURL = directory.appending(path: "Cue/resume-positions.json")
        let json = JSONResumeStore(fileURL: fileURL)
        for (videoID, entry) in entries {
            json.save(entry, for: videoID)
        }
        return fileURL
    }

    @Test func importsPositionsFromThePlayersJSONFile() throws {
        let directory = TestQueue.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let entry = ResumeEntry(position: 42, duration: 213, updatedAt: TestQueue.date)
        let fileURL = writeJSONFile(in: directory, entries: [(TestQueue.first, entry)])
        let store = try TestQueue.store()

        let report = try JSONResumeImport(store: store).runIfNeeded(from: fileURL)

        #expect(report == JSONResumeImport.Report(imported: 1))
        #expect(try store.resumeEntry(for: TestQueue.first) == entry)
    }

    @Test func importsOnlyOnceAndLeavesTheFileAlone() throws {
        let directory = TestQueue.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = writeJSONFile(in: directory, entries: [
            (TestQueue.first, ResumeEntry(position: 42, duration: 213, updatedAt: TestQueue.date)),
        ])
        let store = try TestQueue.store()
        let importer = JSONResumeImport(store: store)

        _ = try importer.runIfNeeded(from: fileURL)
        try store.removeResumeEntry(for: TestQueue.first)
        let second = try importer.runIfNeeded(from: fileURL)

        #expect(second == JSONResumeImport.Report())
        #expect(try store.resumeEntry(for: TestQueue.first) == nil)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func keepsPositionsTheDatabaseAlreadyHas() throws {
        let directory = TestQueue.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = writeJSONFile(in: directory, entries: [
            (TestQueue.first, ResumeEntry(position: 42, duration: 213, updatedAt: TestQueue.date)),
            (TestQueue.second, ResumeEntry(position: 11, duration: 19, updatedAt: TestQueue.date)),
        ])
        let store = try TestQueue.store()
        let newer = ResumeEntry(position: 180, duration: 213, updatedAt: TestQueue.date.addingTimeInterval(60))
        try store.saveResumeEntry(newer, for: TestQueue.first)

        let report = try JSONResumeImport(store: store).runIfNeeded(from: fileURL)

        #expect(report == JSONResumeImport.Report(imported: 1, skipped: 1))
        #expect(try store.resumeEntry(for: TestQueue.first) == newer)
        #expect(try store.resumeEntry(for: TestQueue.second)?.position == 11)
    }

    @Test func countsKeysThatAreNotVideoIds() throws {
        let directory = TestQueue.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "Cue/resume-positions.json")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = """
        {"version": 1, "entries": {"123456789_": {"position": 42, "duration": 213, "updatedAt": "2027-01-15T08:00:00Z"}}}
        """
        try Data(text.utf8).write(to: fileURL)
        let store = try TestQueue.store()

        #expect(try JSONResumeImport(store: store).runIfNeeded(from: fileURL) == JSONResumeImport.Report(invalid: 1))
    }

    @Test func marksTheImportDoneWhenThereIsNoFile() throws {
        let store = try TestQueue.store()
        let missing = TestQueue.temporaryDirectory().appending(path: "resume-positions.json")

        #expect(try JSONResumeImport(store: store).runIfNeeded(from: missing) == JSONResumeImport.Report())
        #expect(try store.metadata(JSONResumeImport.metadataKey) == "done")
    }

    @Test func ignoresAFileWithAnUnexpectedFormatVersion() throws {
        let directory = TestQueue.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appending(path: "resume-positions.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = """
        {"version": 999, "entries": {"dQw4w9WgXcQ": {"position": 42, "duration": 213, "updatedAt": "2027-01-15T08:00:00Z"}}}
        """
        try Data(text.utf8).write(to: fileURL)
        let store = try TestQueue.store()

        #expect(try JSONResumeImport(store: store).runIfNeeded(from: fileURL) == JSONResumeImport.Report())
        #expect(try store.resumeEntry(for: TestQueue.first) == nil)
    }
}
