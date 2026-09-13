import CoreGraphics
import CuePlayer
import Foundation
import Testing

@Suite struct MiniPlayerGeometryTests {
    let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    @Test func keepsTheVideosAspectRatio() {
        let size = MiniPlayerGeometry.size(for: VideoSize(width: 1920, height: 1080), visibleFrame: screen)
        #expect(size == CGSize(width: 480, height: 270))
        // The ratio's two sides are hoisted into constants deliberately. Written inline as
        // `#expect(size.width / size.height == 16.0 / 9.0)` this fails on Swift 6.4, even though both sides are the
        // identical bit pattern 4610685218510194460 and the same comparison is true everywhere outside the macro.
        // Comparing two already-evaluated values is the same check without the macro's expression capture.
        let ratio = size.width / size.height
        let expected: CGFloat = 16.0 / 9.0
        #expect(ratio == expected)
    }

    @Test func usesSixteenByNineWhenTheVideoSizeIsUnknown() {
        let size = MiniPlayerGeometry.size(for: nil, visibleFrame: screen)
        #expect(size == CGSize(width: MiniPlayerGeometry.defaultWidth, height: (MiniPlayerGeometry.defaultWidth * 9 / 16).rounded(.down)))
    }

    @Test func neverGoesBelowTheMinimumWidth() {
        let size = MiniPlayerGeometry.size(for: VideoSize(width: 1920, height: 1080), visibleFrame: CGRect(x: 0, y: 0, width: 200, height: 200))
        #expect(size.width >= MiniPlayerGeometry.minimumWidth)
    }

    @Test func neverTakesMoreThanAFractionOfTheScreen() {
        let size = MiniPlayerGeometry.size(for: VideoSize(width: 3840, height: 2160), visibleFrame: screen)
        #expect(size.width <= screen.width * MiniPlayerGeometry.maximumScreenFraction)
    }

    @Test func sitsInTheBottomRightCornerByDefault() {
        let frame = MiniPlayerGeometry.frame(size: CGSize(width: 400, height: 225), corner: .bottomRight, visibleFrame: screen)
        #expect(frame.maxX == screen.maxX - MiniPlayerGeometry.margin)
        #expect(frame.minY == screen.minY + MiniPlayerGeometry.margin)
    }

    @Test func placesEveryCorner() {
        let size = CGSize(width: 400, height: 225)
        let frames = MiniPlayerGeometry.Corner.allCases.map {
            MiniPlayerGeometry.frame(size: size, corner: $0, visibleFrame: screen)
        }
        #expect(Set(frames.map(\.origin.x)).count == 2)
        #expect(Set(frames.map(\.origin.y)).count == 2)
    }

    @Test func keepsTheMarginFromEveryEdge() {
        for corner in MiniPlayerGeometry.Corner.allCases {
            let frame = MiniPlayerGeometry.frame(size: CGSize(width: 400, height: 225), corner: corner, visibleFrame: screen)
            #expect(screen.insetBy(dx: MiniPlayerGeometry.margin, dy: MiniPlayerGeometry.margin).contains(frame))
        }
    }

    @Test func pullsAFrameBackOntoTheScreen() {
        let frame = MiniPlayerGeometry.clamped(CGRect(x: 1500, y: -300, width: 400, height: 225), visibleFrame: screen)
        #expect(screen.contains(frame))
    }

    @Test func shrinksAFrameBiggerThanTheScreen() {
        let frame = MiniPlayerGeometry.clamped(CGRect(x: 0, y: 0, width: 4000, height: 3000), visibleFrame: screen)
        #expect(frame.width <= screen.width)
        #expect(frame.height <= screen.height)
    }

    @Test func resizingKeepsTheAspectRatio() {
        let size = MiniPlayerGeometry.resized(toWidth: 600, aspectRatio: 16.0 / 9.0, visibleFrame: screen)
        #expect(size == CGSize(width: 600, height: 337))
    }

    @Test func remembersTheCornerAFrameIsNearest() {
        #expect(MiniPlayerGeometry.nearestCorner(of: CGRect(x: 20, y: 900, width: 400, height: 225), visibleFrame: screen) == .topLeft)
        #expect(MiniPlayerGeometry.nearestCorner(of: CGRect(x: 1100, y: 20, width: 400, height: 225), visibleFrame: screen) == .bottomRight)
    }

    @Test func hasNoOpinionAboutTheMainWindowsSize() {
        // The main window's frame is handed back untouched when leaving the mini player: the mini player never resizes it.
        let original = CGRect(x: 100, y: 100, width: 960, height: 540)
        #expect(MiniPlayerGeometry.clamped(original, visibleFrame: screen) == original)
    }
}
