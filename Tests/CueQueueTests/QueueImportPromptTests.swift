@testable import CueQueue
import Testing

@Suite struct QueueImportPromptTests {
    @Test func asksBeforeAddingSeveralLinks() {
        let prompt = QueueImportPresentation.prompt(candidates: 12, unreadable: 0)

        #expect(prompt.message == "Found 12 YouTube links. Add them all?")
        #expect(prompt.detail == nil)
        #expect(prompt.canAdd)
    }

    @Test func speaksOfOneLinkInTheSingular() {
        let prompt = QueueImportPresentation.prompt(candidates: 1, unreadable: 0)

        #expect(prompt.message == "Found 1 YouTube link. Add it?")
        #expect(prompt.detail == nil)
        #expect(prompt.canAdd)
    }

    @Test func admitsTheEntriesItCouldNotRead() {
        let several = QueueImportPresentation.prompt(candidates: 4, unreadable: 3)

        #expect(several.message == "Found 4 YouTube links. Add them all?")
        #expect(several.detail == "3 other lines could not be read as a YouTube link and will be ignored.")
        #expect(several.canAdd)

        let one = QueueImportPresentation.prompt(candidates: 4, unreadable: 1)
        #expect(one.detail == "1 other line could not be read as a YouTube link and will be ignored.")
    }

    @Test func saysWhenTheFileHeldNoLinks() {
        let prompt = QueueImportPresentation.prompt(candidates: 0, unreadable: 0)

        #expect(prompt.message == "That file has no YouTube links.")
        #expect(prompt.detail == "Nothing was added to the queue.")
        #expect(prompt.canAdd == false)
    }

    @Test func countsTheUnreadableLinesOfAFileWithNoLinks() {
        let several = QueueImportPresentation.prompt(candidates: 0, unreadable: 9)

        #expect(several.message == "That file has no YouTube links.")
        #expect(several.detail == "9 lines could not be read as a YouTube link. Nothing was added to the queue.")
        #expect(several.canAdd == false)

        let one = QueueImportPresentation.prompt(candidates: 0, unreadable: 1)
        #expect(one.detail == "1 line could not be read as a YouTube link. Nothing was added to the queue.")
    }
}
