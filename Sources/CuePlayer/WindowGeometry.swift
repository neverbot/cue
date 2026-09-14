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

    /// The window frame whose video area has exactly the video's shape, so mpv draws neither letterbox nor pillarbox
    /// bars. Once the window has been resized by hand there is no way to land on that shape with the mouse, and this
    /// is the arithmetic that lands on it.
    ///
    /// The video area is the content minus `sidebarWidth`, which is zero when the sidebar is hidden or floats over the
    /// picture. The area's current width is kept and its height follows the aspect ratio; only when that would make the
    /// window taller than the screen is the height kept and the width made to follow instead. The result never falls
    /// below `minimumContentSize`, keeps the window's top-left corner — the corner macOS resizes around — and is pushed
    /// back inside `visibleFrame` if it spills off an edge.
    ///
    /// Sizes are whole points: a video area half a point out leaves a hairline bar, which is the defect being fixed, so
    /// the dimension being kept is rounded first and the other derived from it.
    public static func frameFittedToVideo(
        window: CGRect,
        contentSize: CGSize,
        aspectRatio: Double,
        sidebarWidth: CGFloat,
        minimumContentSize: CGSize,
        visibleFrame: CGRect
    ) -> CGRect {
        let aspect = CGFloat(aspectRatio)
        guard aspect > 0, contentSize.width > 0, contentSize.height > 0 else { return window }
        // What the window adds around its content: the title bar, when it is not drawn over the content.
        let chromeWidth = window.width - contentSize.width
        let chromeHeight = window.height - contentSize.height
        let sidebar = min(max(sidebarWidth, 0), contentSize.width)
        let minimumVideoWidth = max(minimumContentSize.width - sidebar, 1)
        let minimumVideoHeight = max(minimumContentSize.height, 1)

        // Candidate A keeps the width the video area already has; candidate B keeps its height, and is used only when
        // A would not fit on the screen vertically.
        let keptWidth = max(contentSize.width - sidebar, 1)
        let video: CGSize
        if keptWidth / aspect + chromeHeight > visibleFrame.height {
            let height = max(contentSize.height, minimumVideoHeight, minimumVideoWidth / aspect).rounded()
            video = CGSize(width: (height * aspect).rounded(), height: height)
        } else {
            let width = max(keptWidth, minimumVideoWidth, minimumVideoHeight * aspect).rounded()
            video = CGSize(width: width, height: (width / aspect).rounded())
        }

        let width = video.width + sidebar + chromeWidth
        let height = video.height + chromeHeight
        var x = window.minX
        var y = window.maxY - height
        if x + width > visibleFrame.maxX { x = visibleFrame.maxX - width }
        if x < visibleFrame.minX { x = visibleFrame.minX }
        if y < visibleFrame.minY { y = visibleFrame.minY }
        if y + height > visibleFrame.maxY { y = visibleFrame.maxY - height }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Whether mpv's reported size differs enough from the size the window was fitted to (1 % in aspect) to refit.
    public static func needsRefit(fittedTo current: VideoSize?, reported: VideoSize) -> Bool {
        guard let current else { return true }
        return abs(current.aspectRatio - reported.aspectRatio) / reported.aspectRatio > 0.01
    }
}
