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

    @Test func requiresPositiveDimensions() {
        #expect(VideoSize(reportedWidth: 1920, reportedHeight: nil) == nil)
        #expect(VideoSize(reportedWidth: 0, reportedHeight: 1080) == nil)
        #expect(VideoSize(reportedWidth: 1920, reportedHeight: 1080) == VideoSize(width: 1920, height: 1080))
    }
}
