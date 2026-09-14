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

    @Test func asksForNoResizeWhenThePictureKeptItsWidth() {
        #expect(WindowGeometry.videoWidthCorrection(before: 960, now: 960) == nil)
        // Fractions of a point are layout arithmetic, not a column: a window nudged by those would never settle.
        #expect(WindowGeometry.videoWidthCorrection(before: 960, now: 959.75) == nil)
    }

    @Test func growsTheWindowByWhatTheColumnTookFromThePicture() {
        let correction = WindowGeometry.videoWidthCorrection(before: 960, now: 680)
        #expect(correction?.width == 280)
        #expect(correction?.appearing == true)
    }

    @Test func shrinksTheWindowByWhatThePictureGainedWhenAColumnClosed() {
        let correction = WindowGeometry.videoWidthCorrection(before: 680, now: 960)
        #expect(correction?.width == 280)
        #expect(correction?.appearing == false)
    }

    /// The window's smallest content size, as the player window sets it.
    let minimumContent = CGSize(width: 320, height: 180)

    /// `videoAreaSize` defaults to the whole window: a player with no column beside it and its title bar drawn over
    /// the picture, which is the plain case.
    private func fitted(
        _ window: CGRect,
        videoAreaSize: CGSize? = nil,
        aspectRatio: Double = 16.0 / 9.0
    ) -> CGRect {
        WindowGeometry.frameFittedToVideo(
            window: window,
            videoAreaSize: videoAreaSize ?? window.size,
            aspectRatio: aspectRatio,
            minimumContentSize: minimumContent,
            visibleFrame: visibleFrame
        )
    }

    @Test func trimsALetterboxedWindowByKeepingItsWidth() {
        // 960 × 700 shows a 16:9 video with bars above and below it; 960 wide wants 540 of height.
        #expect(fitted(CGRect(x: 100, y: 100, width: 960, height: 700))
            == CGRect(x: 100, y: 260, width: 960, height: 540))
    }

    @Test func trimsAPillarboxedWindowByKeepingItsWidth() {
        // 1200 × 540 is too wide for the video, so the window grows downwards to 675 rather than narrowing.
        #expect(fitted(CGRect(x: 100, y: 200, width: 1200, height: 540))
            == CGRect(x: 100, y: 65, width: 1200, height: 675))
    }

    @Test func keepsTheHeightWhenMatchingTheWidthWouldOutgrowTheScreen() {
        // 1400 wide at 4:3 would need 1050 points of height on an 850-point work area, so the width follows instead.
        #expect(fitted(CGRect(x: 0, y: 0, width: 1400, height: 400), aspectRatio: 4.0 / 3.0)
            == CGRect(x: 0, y: 0, width: 533, height: 400))
    }

    @Test func leavesAWindowAlreadyAtTheMinimumSizeWhereItIs() {
        #expect(fitted(CGRect(x: 0, y: 100, width: 320, height: 180))
            == CGRect(x: 0, y: 100, width: 320, height: 180))
    }

    @Test func fitsTheVideoBesideTheSidebarRatherThanTheWholeWindow() {
        // A 960-wide picture measured inside a 1240-wide window: 280 points of sidebar and 28 of title bar. The
        // picture wants 540 of height, and both are added back afterwards.
        #expect(fitted(
            CGRect(x: 100, y: 100, width: 1240, height: 700),
            videoAreaSize: CGSize(width: 960, height: 672)
        ) == CGRect(x: 100, y: 232, width: 1240, height: 568))
    }

    @Test func countsTheDividersASplitViewSpendsBesideThePicture() {
        // The defect this signature exists to prevent: the picture is 958 wide inside a 1240-wide window, because a
        // sidebar and an inspector each cost a divider on top of their 280 and 0 points. Deriving the video area as
        // content-minus-sidebar would call it 960 and leave two points of bar; measuring it lands exactly.
        #expect(fitted(
            CGRect(x: 0, y: 100, width: 1240, height: 700),
            videoAreaSize: CGSize(width: 958, height: 700)
        ) == CGRect(x: 0, y: 261, width: 1240, height: 539))
    }

    @Test func pushesAFittedFrameBackInsideTheScreen() {
        // A square video: the window grows from 200 to 400 points of height below a top edge at 240, which would put
        // its bottom at -160, and it already hung 60 points past the right edge.
        #expect(fitted(CGRect(x: 1100, y: 40, width: 400, height: 200), aspectRatio: 1)
            == CGRect(x: 1040, y: 0, width: 400, height: 400))
    }

    @Test func requiresPositiveDimensions() {
        #expect(VideoSize(reportedWidth: 1920, reportedHeight: nil) == nil)
        #expect(VideoSize(reportedWidth: 0, reportedHeight: 1080) == nil)
        #expect(VideoSize(reportedWidth: 1920, reportedHeight: 1080) == VideoSize(width: 1920, height: 1080))
    }
}
