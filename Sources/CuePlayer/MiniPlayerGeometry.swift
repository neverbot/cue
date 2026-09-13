import CoreGraphics
import Foundation

/// Where the mini player sits and how big it is. Kept apart from the window so the rules can be argued with in tests
/// rather than on screen.
public enum MiniPlayerGeometry {
    public static let defaultWidth: CGFloat = 480
    public static let minimumWidth: CGFloat = 240
    public static let margin: CGFloat = 16
    /// The mini player is a corner of the screen, never a second main window.
    public static let maximumScreenFraction: CGFloat = 0.4

    public enum Corner: String, CaseIterable, Sendable {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    /// The window's content size for a video, clamped between the minimum width and a fraction of the screen.
    public static func size(for video: VideoSize?, visibleFrame: CGRect) -> CGSize {
        let aspect = video.map(\.aspectRatio) ?? 16.0 / 9.0
        let maximum = max(minimumWidth, visibleFrame.width * maximumScreenFraction)
        let width = min(max(defaultWidth, minimumWidth), maximum)
        return CGSize(width: width.rounded(.down), height: (width / CGFloat(aspect)).rounded(.down))
    }

    public static func frame(size: CGSize, corner: Corner, visibleFrame: CGRect) -> CGRect {
        let x = switch corner {
        case .topLeft, .bottomLeft: visibleFrame.minX + margin
        case .topRight, .bottomRight: visibleFrame.maxX - margin - size.width
        }
        let y = switch corner {
        case .bottomLeft, .bottomRight: visibleFrame.minY + margin
        case .topLeft, .topRight: visibleFrame.maxY - margin - size.height
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// A frame entirely on the screen: shrunk if it is larger, moved if it hangs off an edge.
    public static func clamped(_ frame: CGRect, visibleFrame: CGRect) -> CGRect {
        let size = CGSize(width: min(frame.width, visibleFrame.width), height: min(frame.height, visibleFrame.height))
        let x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - size.width)
        let y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - size.height)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// A live resize by the window's right edge: the height follows the width.
    public static func resized(toWidth width: CGFloat, aspectRatio: Double, visibleFrame: CGRect) -> CGSize {
        let clamped = min(max(width, minimumWidth), visibleFrame.width)
        return CGSize(width: clamped.rounded(.down), height: (clamped / CGFloat(aspectRatio)).rounded(.down))
    }

    /// Which corner a moved window is closest to, so the next toggle puts it back where the user left it.
    public static func nearestCorner(of frame: CGRect, visibleFrame: CGRect) -> Corner {
        let isLeft = frame.midX < visibleFrame.midX
        let isTop = frame.midY >= visibleFrame.midY
        return switch (isTop, isLeft) {
        case (true, true): .topLeft
        case (true, false): .topRight
        case (false, true): .bottomLeft
        case (false, false): .bottomRight
        }
    }
}
