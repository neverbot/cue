import Testing
@testable import CueCore

@Suite struct VideoIDTests {
    @Test(arguments: [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtube.com/watch?v=dQw4w9WgXcQ&t=43s",
        "https://m.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ?si=abc",
        "https://www.youtube.com/shorts/dQw4w9WgXcQ",
        "https://www.youtube.com/embed/dQw4w9WgXcQ",
        "https://www.youtube.com/live/dQw4w9WgXcQ",
        "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ",
        "www.youtube.com/watch?v=dQw4w9WgXcQ",
        "  dQw4w9WgXcQ  ",
        "HTTPS://WWW.YOUTUBE.COM/watch?v=dQw4w9WgXcQ",
        "http://youtu.be/dQw4w9WgXcQ/",
        "https://music.youtube.com/watch?feature=share&v=dQw4w9WgXcQ",
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ#t=10",
        "youtube.com/watch?v=dQw4w9WgXcQ&next=https://example.com",
    ])
    func parsesSupportedForms(_ input: String) {
        #expect(VideoID(url: input)?.rawValue == "dQw4w9WgXcQ")
    }

    @Test(arguments: [
        "https://www.youtube.com/",
        "https://www.youtube.com/@YouTube",
        "https://www.youtube.com/results?search_query=x",
        "https://vimeo.com/123456",
        "123456789_",
        "not a url",
        "https://notyoutube.com/watch?v=dQw4w9WgXcQ",
        "https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ",
        "https://www.youtube.com/embed/videoseries?list=PLx",
        "https://www.youtube.com/embed/live_stream?channel=UCx",
    ])
    func rejectsNonVideoInputs(_ input: String) {
        #expect(VideoID(url: input) == nil)
    }

    @Test func validatesRawIdentifiers() {
        #expect(VideoID("jNQXAC9IVRw") != nil)
        #expect(VideoID("123456789_!") == nil)
        #expect(VideoID("123456789_ab") == nil)
        #expect(VideoID("12345678-_a") != nil)
        #expect(VideoID("123456789_é") == nil)
    }
}
