import CoreGraphics
import Foundation

/// A video's display size in pixels (pixel aspect ratio and rotation already applied).
public struct VideoSize: Equatable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// Nil unless both dimensions are known and positive.
    public init?(reportedWidth width: Int?, reportedHeight height: Int?) {
        guard let width, let height, width > 0, height > 0 else { return nil }
        self.init(width: width, height: height)
    }

    public var aspectRatio: Double { Double(width) / Double(height) }
}

public enum WindowGeometry {
    public static let minimumContentWidth: CGFloat = 480
    public static let screenFraction: CGFloat = 0.8
    public static let defaultContentSize = CGSize(width: 960, height: 540)

    /// The video's pixels as points, at least `minimumContentWidth` wide, scaled down to fit `screenFraction` of the
    /// visible screen area. The aspect ratio is kept; sizes are whole points, rounded down.
    public static func contentSize(for video: VideoSize, visibleScreenSize: CGSize) -> CGSize {
        let videoWidth = CGFloat(video.width)
        let videoHeight = CGFloat(video.height)
        let width = max(videoWidth, minimumContentWidth)
        let height = width * videoHeight / videoWidth
        let scale = min(1, visibleScreenSize.width * screenFraction / width, visibleScreenSize.height * screenFraction / height)
        let fittedWidth = (width * scale).rounded(.down)
        return CGSize(width: fittedWidth, height: (fittedWidth * videoHeight / videoWidth).rounded(.down))
    }

    /// The window frame that leaves the video area exactly the size it already had when the sidebar appears beside it
    /// or goes away. The sidebar's width is taken from the window rather than from the picture, so mpv is never asked
    /// to letterbox a video it had already fitted.
    ///
    /// The window grows rightwards until the screen's edge and then leftwards. If the screen is still too narrow, what
    /// fits is kept and the video area absorbs the remainder, which is better than a window hanging off the display.
    /// It never ends up smaller than `minimumSize` nor outside `visibleFrame`; the height is left alone.
    public static func frameAdjustedForSidebar(
        window: CGRect,
        sidebarWidth: CGFloat,
        appearing: Bool,
        minimumSize: CGSize,
        visibleFrame: CGRect
    ) -> CGRect {
        let wanted = window.width + (appearing ? sidebarWidth : -sidebarWidth)
        let width = min(max(wanted, minimumSize.width), max(visibleFrame.width, minimumSize.width))
        var x = window.minX
        if x + width > visibleFrame.maxX { x = visibleFrame.maxX - width }
        if x < visibleFrame.minX { x = visibleFrame.minX }
        return CGRect(x: x, y: window.minY, width: width, height: max(window.height, minimumSize.height))
    }

    /// Whether mpv's reported size differs enough from the size the window was fitted to (1 % in aspect) to refit.
    public static func needsRefit(fittedTo current: VideoSize?, reported: VideoSize) -> Bool {
        guard let current else { return true }
        return abs(current.aspectRatio - reported.aspectRatio) / reported.aspectRatio > 0.01
    }
}
