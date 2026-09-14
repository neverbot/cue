import CoreGraphics
@testable import CuePlayer
import Testing

@Suite struct WindowGeometryTests {
    let screen = CGSize(width: 2000, height: 1250)

    @Test func scalesLargeVideosToEightyPercentOfTheScreen() {
        #expect(WindowGeometry.contentSize(for: VideoSize(width: 1920, height: 1080), visibleScreenSize: screen) == CGSize(width: 1600, height: 900))
    }

    @Test func enlargesSmallVideosToTheMinimumWidth() {
        #expect(WindowGeometry.contentSize(for: VideoSize(width: 320, height: 240), visibleScreenSize: screen) == CGSize(width: 480, height: 360))
    }

    @Test func fitsPortraitVideosByHeight() {
        #expect(WindowGeometry.contentSize(for: VideoSize(width: 1080, height: 1920), visibleScreenSize: screen) == CGSize(width: 562, height: 999))
    }

    @Test func keepsVideoPixelsAsPointsWhenTheyFit() {
        #expect(WindowGeometry.contentSize(for: VideoSize(width: 1280, height: 720), visibleScreenSize: screen) == CGSize(width: 1280, height: 720))
    }

    @Test func refitsOnlyWhenTheAspectRatioChanges() {
        let fitted = VideoSize(width: 1920, height: 1080)
        #expect(!WindowGeometry.needsRefit(fittedTo: fitted, reported: VideoSize(width: 1280, height: 720)))
        #expect(!WindowGeometry.needsRefit(fittedTo: fitted, reported: VideoSize(width: 1920, height: 1088)))
        #expect(WindowGeometry.needsRefit(fittedTo: fitted, reported: VideoSize(width: 1440, height: 1080)))
        #expect(WindowGeometry.needsRefit(fittedTo: nil, reported: fitted))
    }

    /// A 1440 × 850 work area with its origin at zero, and a sidebar the width the queue actually uses.
    let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 850)
    let sidebar: CGFloat = 280
    let minimum = CGSize(width: 320, height: 208)

    private func adjusted(_ window: CGRect, appearing: Bool) -> CGRect {
        WindowGeometry.frameAdjustedForSidebar(
            window: window,
            sidebarWidth: sidebar,
            appearing: appearing,
            minimumSize: minimum,
            visibleFrame: visibleFrame
        )
    }

    @Test func growsByTheSidebarWidthWhenTheScreenHasRoom() {
        #expect(adjusted(CGRect(x: 100, y: 100, width: 960, height: 540), appearing: true)
            == CGRect(x: 100, y: 100, width: 1240, height: 540))
    }

    @Test func growsLeftwardsOnceItReachesTheScreensRightEdge() {
        // 400 + 1240 would end at 1640, past the work area, so the window slides left instead of hanging off it.
        #expect(adjusted(CGRect(x: 400, y: 100, width: 960, height: 540), appearing: true)
            == CGRect(x: 200, y: 100, width: 1240, height: 540))
    }

    @Test func keepsWhatFitsWhenTheScreenIsTooNarrowToGrow() {
        // The video area absorbs the 140 points the screen cannot give.
        #expect(adjusted(CGRect(x: 100, y: 100, width: 1300, height: 540), appearing: true)
            == CGRect(x: 0, y: 100, width: 1440, height: 540))
    }

    @Test func shrinksByTheSidebarWidthAndKeepsItsLeftEdge() {
        #expect(adjusted(CGRect(x: 200, y: 100, width: 1240, height: 540), appearing: false)
            == CGRect(x: 200, y: 100, width: 960, height: 540))
    }

    @Test func neverShrinksBelowTheMinimumContentSize() {
        #expect(adjusted(CGRect(x: 0, y: 100, width: 320, height: 208), appearing: false)
            == CGRect(x: 0, y: 100, width: 320, height: 208))
    }

    @Test func requiresPositiveDimensions() {
        #expect(VideoSize(reportedWidth: 1920, reportedHeight: nil) == nil)
        #expect(VideoSize(reportedWidth: 0, reportedHeight: 1080) == nil)
        #expect(VideoSize(reportedWidth: 1920, reportedHeight: 1080) == VideoSize(width: 1920, height: 1080))
    }
}
