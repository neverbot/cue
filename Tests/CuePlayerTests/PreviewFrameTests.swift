import CueCore
import CuePlayer
import Foundation
import Testing

@Suite struct PreviewFrameTests {
    static let spec = StoryboardSpec(
        "https://i.ytimg.com/sb/12345678-_a/storyboard3_L$L/$N.jpg?sqp=test"
            + "|48#27#100#10#10#0#default#rs$test"
            + "|160#90#108#5#5#2000#M$M#rs$test"
    )!

    @Test func mapsAnXToASecond() {
        #expect(SeekBarGeometry.seconds(atX: 50, width: 100, duration: 200) == 100)
    }

    @Test func clampsAnXOutsideTheBar() {
        #expect(SeekBarGeometry.seconds(atX: -20, width: 100, duration: 200) == 0)
        #expect(SeekBarGeometry.seconds(atX: 300, width: 100, duration: 200) == 200)
    }

    @Test func hasNoTimeForAnEmptyBar() {
        #expect(SeekBarGeometry.seconds(atX: 10, width: 0, duration: 200) == nil)
        #expect(SeekBarGeometry.seconds(atX: 10, width: 100, duration: nil) == nil)
    }

    @Test func mapsAPositionBackToAnX() {
        #expect(SeekBarGeometry.x(forSeconds: 50, width: 100, duration: 200) == 25)
        #expect(SeekBarGeometry.x(forSeconds: 500, width: 100, duration: 200) == 100)
    }

    @Test func mapsAFractionToAnXOnTheInsetTrack() {
        #expect(SeekBarGeometry.x(forFraction: 0, width: 100, inset: 6) == 6)
        #expect(SeekBarGeometry.x(forFraction: 0.5, width: 100, inset: 6) == 56)
        #expect(SeekBarGeometry.x(forFraction: 1, width: 100, inset: 6) == 106)
    }

    @Test func clampsAFractionOutsideTheTrack() {
        #expect(SeekBarGeometry.x(forFraction: -0.5, width: 100, inset: 6) == 6)
        #expect(SeekBarGeometry.x(forFraction: 1.5, width: 100, inset: 6) == 106)
    }

    /// A bar narrower than its own knob has nowhere to put a tick but the inset.
    @Test func putsEveryFractionAtTheInsetOnAZeroWidthTrack() {
        #expect(SeekBarGeometry.x(forFraction: 0.5, width: 0, inset: 6) == 6)
        #expect(SeekBarGeometry.x(forFraction: 1, width: 0, inset: 6) == 6)
    }

    @Test func picksTheFrameForTheHoveredSecond() throws {
        let frame = try #require(PreviewFrame.frame(at: 61, duration: 213, storyboard: Self.spec))
        #expect(frame.width == 160)
        #expect(frame.sheet == 1)
        #expect(frame.column == 0)
        #expect(frame.row == 1)
    }

    @Test func hasNoFrameWithoutASpec() {
        #expect(PreviewFrame.frame(at: 61, duration: 213, storyboard: nil) == nil)
    }

    @Test func keepsThePopoverInsideTheBarAtTheLeftEdge() {
        #expect(PreviewFrame.popoverX(centredOn: 2, popoverWidth: 160, barWidth: 600) == 0)
    }

    @Test func keepsThePopoverInsideTheBarAtTheRightEdge() {
        #expect(PreviewFrame.popoverX(centredOn: 598, popoverWidth: 160, barWidth: 600) == 440)
    }
}
