import CueCore
import CuePlayer
@testable import CueQueue
import Foundation
import Testing

@Suite struct QueueImportTests {
    @Test func readsAURLList() throws {
        let text = """
        # a comment
        https://www.youtube.com/watch?v=dQw4w9WgXcQ

        https://youtu.be/jNQXAC9IVRw
        not a video
        """
        let (candidates, unreadable) = try QueueImport.candidates(in: text, format: .urlList)

        #expect(candidates.map(\.videoID) == [TestQueue.first, TestQueue.second])
        #expect(unreadable == ["not a video"])
    }

    @Test func dropsRepeatsWithinAURLList() throws {
        let text = "https://youtu.be/dQw4w9WgXcQ\nhttps://www.youtube.com/watch?v=dQw4w9WgXcQ\n"
        let (candidates, _) = try QueueImport.candidates(in: text, format: .urlList)

        #expect(candidates.count == 1)
    }

    @Test func readsCueJSON() throws {
        let text = """
        {"version": 1, "items": [
          {"videoID": "dQw4w9WgXcQ", "title": "First", "author": "Author", "duration": 213,
           "addedAt": "2027-01-15T08:00:00Z", "watchedAt": "2027-01-16T08:00:00Z"},
          {"videoID": "jNQXAC9IVRw", "title": "Second"}
        ]}
        """
        let (candidates, unreadable) = try QueueImport.candidates(in: text, format: .json)

        #expect(unreadable.isEmpty)
        #expect(candidates.count == 2)
        #expect(candidates[0].title == "First")
        #expect(candidates[0].author == "Author")
        #expect(candidates[0].duration == 213)
        #expect(candidates[0].watchedAt != nil)
        #expect(candidates[1].videoID == TestQueue.second)
        #expect(candidates[1].watchedAt == nil)
    }

    /// A JSON import must not silently drop an item its id validation rejects: it is reported as unreadable, exactly
    /// like the URL-list and CSV formats.
    @Test func reportsAJSONItemWithAnUnreadableID() throws {
        let text = """
        {"version": 1, "items": [
          {"videoID": "dQw4w9WgXcQ", "title": "Good"},
          {"videoID": "not-a-video-id"}
        ]}
        """
        let (candidates, unreadable) = try QueueImport.candidates(in: text, format: .json)

        #expect(candidates.map(\.videoID) == [TestQueue.first])
        #expect(unreadable == ["not-a-video-id"])
    }

    @Test func refusesJSONItCannotRead() {
        #expect(throws: QueueImport.ImportError.unreadableJSON) {
            try QueueImport.candidates(in: "not json", format: .json)
        }
    }

    @Test func refusesAFutureJSONVersion() {
        #expect(throws: QueueImport.ImportError.unsupportedJSONVersion(999)) {
            try QueueImport.candidates(in: #"{"version": 999, "items": []}"#, format: .json)
        }
    }

    @Test func readsATakeoutStyleCSV() throws {
        let text = """
        Video ID,Playlist Video Creation Timestamp
        dQw4w9WgXcQ,2027-01-15T08:00:00+00:00
        jNQXAC9IVRw,2027-01-16T08:00:00.123+00:00
        """
        let (candidates, unreadable) = try QueueImport.candidates(in: text, format: .csv)

        #expect(unreadable.isEmpty)
        #expect(candidates.map(\.videoID) == [TestQueue.first, TestQueue.second])
        #expect(candidates[0].addedAt == TestQueue.date)
        #expect(candidates[1].addedAt != nil)
    }

    @Test func readsCuesOwnWiderCSV() throws {
        let text = """
        Video ID,Title,Author,Duration Seconds,Added Timestamp,Watched Timestamp
        "dQw4w9WgXcQ","A title, with a comma","Author",213,"2027-01-15T08:00:00Z",""
        """
        let (candidates, _) = try QueueImport.candidates(in: text, format: .csv)

        #expect(candidates.count == 1)
        #expect(candidates[0].title == "A title, with a comma")
        #expect(candidates[0].author == "Author")
        #expect(candidates[0].duration == 213)
        #expect(candidates[0].watchedAt == nil)
    }

    /// Quotes are what say the spaces belong to the value, so a quoted field is kept exactly as written; an unquoted
    /// one is trimmed, because spreadsheets pad them.
    @Test func keepsWhitespaceInsideQuotedCSVFieldsAndTrimsUnquotedOnes() throws {
        let text = """
        Video ID,Title,Author
        dQw4w9WgXcQ,"  Spaced title  ",  Padded author
        """
        let (candidates, _) = try QueueImport.candidates(in: text, format: .csv)

        #expect(candidates.count == 1)
        #expect(candidates[0].title == "  Spaced title  ")
        #expect(candidates[0].author == "Padded author")
    }

    @Test func readsCSVColumnsInAnyOrderIgnoringCase() throws {
        let text = """
        TITLE,video url
        Something,https://www.youtube.com/watch?v=dQw4w9WgXcQ
        """
        let (candidates, _) = try QueueImport.candidates(in: text, format: .csv)

        #expect(candidates.map(\.videoID) == [TestQueue.first])
        #expect(candidates[0].title == "Something")
    }

    @Test func reportsCSVRowsWithoutAVideo() throws {
        let text = """
        Video ID,Title
        dQw4w9WgXcQ,First
        nonsense,Second
        """
        let (candidates, unreadable) = try QueueImport.candidates(in: text, format: .csv)

        #expect(candidates.count == 1)
        #expect(unreadable == ["nonsense,Second"])
    }

    @Test func readsAHeaderlessCSVAsIdsInTheFirstColumn() throws {
        let text = "dQw4w9WgXcQ,ignored\njNQXAC9IVRw,ignored\n"
        let (candidates, unreadable) = try QueueImport.candidates(in: text, format: .csv)

        #expect(candidates.map(\.videoID) == [TestQueue.first, TestQueue.second])
        #expect(unreadable.isEmpty)
    }

    @Test func detectsTheFormatFromTheExtensionThenTheContents() {
        #expect(QueueFormat.detect(fileExtension: "json", contents: "") == .json)
        #expect(QueueFormat.detect(fileExtension: "CSV", contents: "") == .csv)
        #expect(QueueFormat.detect(fileExtension: "txt", contents: "{}") == .urlList)
        #expect(QueueFormat.detect(fileExtension: nil, contents: #"{"version": 1}"#) == .json)
        #expect(QueueFormat.detect(fileExtension: nil, contents: "Video ID,Title\ndQw4w9WgXcQ,x") == .csv)
        #expect(QueueFormat.detect(fileExtension: nil, contents: "https://youtu.be/dQw4w9WgXcQ") == .urlList)
    }

    /// Unlike `detect`, an extensionless save-panel name must not fall back to the lossy URL list: it defaults to
    /// the format that keeps everything.
    @Test func exportDefaultsToJSONWhenTheNameHasNoExtension() {
        #expect(QueueFormat.detectForExport(fileExtension: "") == .json)
        #expect(QueueFormat.detectForExport(fileExtension: nil) == .json)
        #expect(QueueFormat.detectForExport(fileExtension: "csv") == .csv)
        #expect(QueueFormat.detectForExport(fileExtension: "txt") == .urlList)
    }

    @Test func addsCandidatesAndReportsWhatItSkipped() throws {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, title: "Already here", addedAt: TestQueue.date)
        let candidates = [
            ImportCandidate(videoID: TestQueue.first, title: "From the file"),
            ImportCandidate(videoID: TestQueue.second, title: "New", duration: 19, addedAt: TestQueue.date),
        ]

        let report = try QueueImport.apply(candidates, unreadable: ["junk"], to: store, now: TestQueue.date)

        #expect(report == ImportReport(added: 1, duplicates: 1, unreadable: ["junk"]))
        #expect(try store.video(for: TestQueue.first)?.title == "Already here")
        #expect(try store.video(for: TestQueue.second)?.duration == 19)
    }

    @Test func importingTheSameFileTwiceChangesNothing() throws {
        let store = try TestQueue.store()
        let text = "https://youtu.be/dQw4w9WgXcQ\nhttps://youtu.be/jNQXAC9IVRw\n"
        let (candidates, unreadable) = try QueueImport.candidates(in: text, format: .urlList)

        let first = try QueueImport.apply(candidates, unreadable: unreadable, to: store, now: TestQueue.date)
        let second = try QueueImport.apply(candidates, unreadable: unreadable, to: store, now: TestQueue.date)

        #expect(first == ImportReport(added: 2))
        #expect(second == ImportReport(duplicates: 2))
        #expect(try store.videos().count == 2)
    }

    @Test func marksImportedVideosThatWereAlreadyWatched() throws {
        let store = try TestQueue.store()
        let candidate = ImportCandidate(videoID: TestQueue.first, title: "Seen", watchedAt: TestQueue.date)

        _ = try QueueImport.apply([candidate], to: store, now: TestQueue.date)

        #expect(try store.video(for: TestQueue.first)?.isWatched == true)
    }

    @Test func summarisesAReportInOneLine() {
        #expect(ImportReport(added: 1).summary == "Added 1 video.")
        #expect(ImportReport(added: 3, duplicates: 2, unreadable: ["a"]).summary
            == "Added 3 videos, skipped 2 already queued, ignored 1 unreadable line.")
    }
}

@Suite struct QueueExportTests {
    private func store() throws -> QueueStore {
        let store = try TestQueue.store()
        try store.add(TestQueue.first, title: "First", author: "Author", duration: 213, addedAt: TestQueue.date)
        try store.add(TestQueue.second, title: "Second, quoted \"here\"", addedAt: TestQueue.date)
        return store
    }

    @Test func writesAURLListOnePerLine() throws {
        let text = QueueExport.urlList(try store().videos())

        #expect(text == """
        https://www.youtube.com/watch?v=dQw4w9WgXcQ
        https://www.youtube.com/watch?v=jNQXAC9IVRw

        """)
    }

    @Test func writesJSONThatImportsBackIdentically() throws {
        let exported = try QueueExport.json(try store().videos())
        let (candidates, unreadable) = try QueueImport.candidates(in: exported, format: .json)

        #expect(unreadable.isEmpty)
        #expect(candidates.map(\.videoID) == [TestQueue.first, TestQueue.second])
        #expect(candidates[0].title == "First")
        #expect(candidates[0].author == "Author")
        #expect(candidates[0].duration == 213)
        #expect(candidates[0].addedAt == TestQueue.date)
        #expect(candidates[1].title == "Second, quoted \"here\"")
    }

    @Test func writesCSVThatImportsBackIdentically() throws {
        let exported = QueueExport.csv(try store().videos())
        let (candidates, unreadable) = try QueueImport.candidates(in: exported, format: .csv)

        #expect(exported.hasPrefix("Video ID,Title,Author,Duration Seconds,Added Timestamp,Watched Timestamp\n"))
        #expect(unreadable.isEmpty)
        #expect(candidates.map(\.videoID) == [TestQueue.first, TestQueue.second])
        #expect(candidates[0].duration == 213)
        #expect(candidates[1].title == "Second, quoted \"here\"")
    }

    @Test func keepsTheWatchedStateThroughAJSONRoundTrip() throws {
        let store = try store()
        try store.markWatched(TestQueue.first, at: TestQueue.date)
        let exported = try QueueExport.json(try store.videos())

        let (candidates, _) = try QueueImport.candidates(in: exported, format: .json)
        #expect(candidates[0].watchedAt == TestQueue.date)
        #expect(candidates[1].watchedAt == nil)
    }

    @Test func namesFilesAfterTheDateAndNothingElse() {
        #expect(QueueExport.suggestedFileName(for: .json, on: TestQueue.date) == "cue-queue-2027-01-15.json")
        #expect(QueueExport.suggestedFileName(for: .urlList, on: TestQueue.date) == "cue-queue-2027-01-15.txt")
        #expect(QueueExport.suggestedFileName(for: .csv, on: TestQueue.date) == "cue-queue-2027-01-15.csv")
    }

    @Test func exportsAnEmptyQueueWithoutFailing() throws {
        let store = try TestQueue.store()
        #expect(QueueExport.urlList(try store.videos()) == "")
        #expect(QueueExport.csv(try store.videos()).hasPrefix("Video ID,"))

        let json = try QueueExport.json(try store.videos())
        #expect(json.contains("\"items\""))
        #expect(try QueueImport.candidates(in: json, format: .json).candidates.isEmpty)
    }
}
