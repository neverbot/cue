import CueCore
@testable import CuePlayer
import Foundation
import Testing

@Suite struct LaunchInputTests {
    @Test func readsAVideoURLAfterAppKitArguments() {
        let arguments = ["-ApplePersistenceIgnoreState", "YES", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"]
        #expect(LaunchInput.parse(arguments: arguments) == .video(VideoID("dQw4w9WgXcQ")!))
    }

    @Test func skipsProcessSerialNumbers() {
        #expect(LaunchInput.parse(arguments: ["-psn_0_12345", "jNQXAC9IVRw"]) == .video(VideoID("jNQXAC9IVRw")!))
    }

    @Test func readsVideoIdsThatStartWithADash() {
        #expect(LaunchInput.parse(arguments: ["-123456789_"]) == .video(VideoID("-123456789_")!))
    }

    @Test func skipsCueFlags() {
        let arguments = ["--smoke-hide", "--smoke-test", "3", "jNQXAC9IVRw"]
        #expect(LaunchInput.parse(arguments: arguments) == .video(VideoID("jNQXAC9IVRw")!))
    }

    @Test func opensLocalFiles() {
        #expect(LaunchInput.parse(arguments: ["--file", "/tmp/test clip.mp4"]) == .file(URL(fileURLWithPath: "/tmp/test clip.mp4")))
    }

    @Test func returnsNilWithoutAVideo() {
        #expect(LaunchInput.parse(arguments: []) == nil)
        #expect(LaunchInput.parse(arguments: ["not a video"]) == nil)
    }

    @Test func readsTheFirstVideoLineOfPastedText() {
        #expect(LaunchInput.parse(pastedText: "watch this\nhttps://youtu.be/jNQXAC9IVRw\n") == .video(VideoID("jNQXAC9IVRw")!))
        #expect(LaunchInput.parse(pastedText: "123456789_") == nil)
        #expect(LaunchInput.parse(pastedText: nil) == nil)
    }
}
