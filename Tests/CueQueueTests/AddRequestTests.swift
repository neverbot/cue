import CueCore
@testable import CueQueue
import Foundation
import Testing

@Suite struct AddRequestTests {
    @Test func readsTheVideoFromAnAddLink() throws {
        let url = URL(string: "cue://add?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DdQw4w9WgXcQ")!
        #expect(try AddRequest.videoID(from: url) == TestQueue.first)
    }

    @Test func acceptsAShortLinkAndABareIdInTheParameter() throws {
        #expect(try AddRequest.videoID(from: URL(string: "cue://add?url=https://youtu.be/jNQXAC9IVRw")!) == TestQueue.second)
        #expect(try AddRequest.videoID(from: URL(string: "cue://add?url=dQw4w9WgXcQ")!) == TestQueue.first)
    }

    @Test func rejectsALinkThatIsNotACueAddLink() {
        #expect(throws: AddRequestError.notACueLink("cue://play?url=dQw4w9WgXcQ")) {
            try AddRequest.videoID(from: URL(string: "cue://play?url=dQw4w9WgXcQ")!)
        }
        #expect(throws: AddRequestError.notACueLink("https://www.youtube.com/watch?v=dQw4w9WgXcQ")) {
            try AddRequest.videoID(from: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!)
        }
    }

    @Test func rejectsAnAddLinkWithoutAURLParameter() {
        #expect(throws: AddRequestError.missingURLParameter) {
            try AddRequest.videoID(from: URL(string: "cue://add")!)
        }
        #expect(throws: AddRequestError.missingURLParameter) {
            try AddRequest.videoID(from: URL(string: "cue://add?url=")!)
        }
    }

    @Test func rejectsSomethingThatIsNotAYouTubeVideo() {
        #expect(throws: AddRequestError.notAYouTubeVideo("https://example.invalid/watch?v=123456789_")) {
            try AddRequest.videoID(from: URL(string: "cue://add?url=https://example.invalid/watch%3Fv%3D123456789_")!)
        }
    }

    @Test func everyErrorExplainsItself() {
        let errors: [AddRequestError] = [
            .notACueLink("x"), .missingURLParameter, .notAYouTubeVideo("y"), .noVideoFound,
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test func buildsTheLinkOtherAppsOpen() throws {
        let url = AddRequest.url(adding: TestQueue.first)

        #expect(url.scheme == "cue")
        #expect(url.host() == "add")
        #expect(try AddRequest.videoID(from: url) == TestQueue.first)
    }

    @Test func readsEveryVideoFromALinkCarryingSeveral() throws {
        let url = URL(string: "cue://add?url=dQw4w9WgXcQ&url=https://youtu.be/jNQXAC9IVRw")!
        #expect(try AddRequest.videoIDs(from: url) == [TestQueue.first, TestQueue.second])
    }

    @Test func ignoresRepeatsWithinOneLink() throws {
        let url = URL(string: "cue://add?url=dQw4w9WgXcQ&url=jNQXAC9IVRw&url=dQw4w9WgXcQ")!
        #expect(try AddRequest.videoIDs(from: url) == [TestQueue.first, TestQueue.second])
    }

    @Test func keepsTheUsableVideosWhenOneParameterIsNot() throws {
        let url = URL(string: "cue://add?url=dQw4w9WgXcQ&url=https://example.invalid/page&url=jNQXAC9IVRw")!
        #expect(try AddRequest.videoIDs(from: url) == [TestQueue.first, TestQueue.second])
    }

    @Test func refusesALinkWhereNoParameterIsAVideo() {
        #expect(throws: AddRequestError.notAYouTubeVideo("https://example.invalid/page")) {
            try AddRequest.videoIDs(from: URL(string: "cue://add?url=https://example.invalid/page&url=123456789_")!)
        }
    }

    @Test func buildsOneLinkForSeveralVideos() throws {
        let url = AddRequest.url(adding: [TestQueue.first, TestQueue.second])

        #expect(url.scheme == "cue")
        #expect(url.host() == "add")
        #expect(try AddRequest.videoIDs(from: url) == [TestQueue.first, TestQueue.second])
    }

    @Test func refusesALinkBuiltFromNoVideosAtAll() {
        #expect(throws: AddRequestError.missingURLParameter) {
            try AddRequest.videoIDs(from: AddRequest.url(adding: []))
        }
    }

    @Test func findsEveryVideoInPastedText() {
        let text = """
        https://www.youtube.com/watch?v=dQw4w9WgXcQ
        not a link
        https://youtu.be/jNQXAC9IVRw?t=42
        https://www.youtube.com/watch?v=dQw4w9WgXcQ
        """

        #expect(AddRequest.videoIDs(in: text) == [TestQueue.first, TestQueue.second])
    }

    @Test func findsNothingInTextWithoutVideos() {
        #expect(AddRequest.videoIDs(in: "https://example.invalid/page\n\n").isEmpty)
    }

    @Test func readsDroppedItemsAsText() {
        let items = ["https://youtu.be/dQw4w9WgXcQ", "https://www.youtube.com/watch?v=jNQXAC9IVRw"]
        #expect(AddRequest.videoIDs(inDropped: items) == [TestQueue.first, TestQueue.second])
    }
}
