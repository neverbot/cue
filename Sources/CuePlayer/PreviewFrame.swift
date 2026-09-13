import CoreGraphics
import CueCore
import Foundation

/// Maps between a seek bar's width in points and a video's seconds. Both directions clamp, so a pointer dragged past
/// either end of the bar means the end of the bar and not a seek to nowhere.
public enum SeekBarGeometry {
    /// The second a point on the bar stands for. Nil when the bar has no width or the duration is unknown.
    public static func seconds(atX x: CGFloat, width: CGFloat, duration: Double?) -> Double? {
        guard width > 0, let duration, duration > 0 else { return nil }
        return min(max(Double(x / width), 0), 1) * duration
    }

    /// Where a second sits on the bar.
    public static func x(forSeconds seconds: Double, width: CGFloat, duration: Double?) -> CGFloat {
        guard let duration, duration > 0 else { return 0 }
        return width * CGFloat(min(max(seconds / duration, 0), 1))
    }
}

/// Which storyboard frame a hover wants, and where the bubble showing it goes.
public enum PreviewFrame {
    /// The frame at `seconds`, taken from the largest level the spec offers.
    public static func frame(at seconds: Double, duration: Double?, storyboard: StoryboardSpec?) -> StoryboardSpec.Frame? {
        guard let storyboard, let level = storyboard.bestLevel else { return nil }
        return storyboard.frame(at: seconds, duration: duration, level: level)
    }

    /// The popover's left edge: centred on the pointer, but never hanging off either end of the bar.
    public static func popoverX(centredOn x: CGFloat, popoverWidth: CGFloat, barWidth: CGFloat) -> CGFloat {
        min(max(x - popoverWidth / 2, 0), max(barWidth - popoverWidth, 0))
    }
}
