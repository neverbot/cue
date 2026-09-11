import Testing
@testable import CueCore

@Suite struct WatchPageTests {
    @Test func extractsVisitorData() throws {
        let html = try Fixture.string("watch-page-snippet.html")
        #expect(WatchPage.visitorData(in: html) == "CgtTRVNUVklTSVRPUg%3D%3D")
    }

    @Test func returnsNilWithoutVisitorData() {
        #expect(WatchPage.visitorData(in: "<html>consent page</html>") == nil)
    }

    @Test func firstCaptureReturnsFirstGroup() {
        #expect(firstCapture(#"id=(\d+)"#, in: "a id=42 b id=7") == "42")
        #expect(firstCapture(#"id=(\d+)"#, in: "nothing") == nil)
    }
}
