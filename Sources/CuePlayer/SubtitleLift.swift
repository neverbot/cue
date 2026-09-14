import Foundation

/// Where the subtitles sit while the floating controls are on screen.
///
/// The controls bar is drawn over the bottom of the picture, which is exactly where subtitles are drawn, so while the
/// bar is visible the two overlap and the text underneath becomes unreadable. Rather than move the bar or dim the
/// text, the subtitles are lifted clear of it and put back where they were when it fades.
///
/// This is the decision, not the drawing: what the lift should be is arithmetic over two measurements, so it lives
/// here beside `SubtitleStyle` where it can be tested, and the window only supplies the numbers and sends the result.
public enum SubtitleLift {
    /// The property mpv positions subtitles with, shared with `SubtitleStyle` so the two cannot drift apart.
    public static let positionProperty = "sub-pos"

    /// What mpv accepts for `sub-pos`: a percentage of the picture's height, 100 being the bottom and the default.
    public static let range: ClosedRange<Double> = 0...150

    /// The position to send, given the user's own resting position and how much of the bottom of the picture is
    /// covered right now.
    ///
    /// `occludedHeight` and `pictureHeight` are both in points, while `sub-pos` is a percentage of the picture's
    /// height — so the lift is the covered fraction expressed in those units and taken off the baseline. The user's
    /// setting is that baseline and is never replaced: with nothing covered the answer is exactly what they chose.
    ///
    /// A picture with no measurable height — a window that has not laid out yet — is left alone rather than guessed
    /// at, which is also what makes applying this harmless when no subtitle is showing at all.
    public static func position(baseline: Double, occludedHeight: Double, pictureHeight: Double) -> Double {
        let resting = clamped(baseline)
        guard pictureHeight > 0, occludedHeight > 0 else { return resting }
        let lift = (occludedHeight / pictureHeight) * 100
        // Clamped rather than allowed to go negative: mpv refuses a value outside the range, and a bar taller than
        // the picture it floats over is a real case in a very short window.
        return clamped(resting - lift)
    }

    /// The same decision as a command, so the window has no value to format and no property name to repeat.
    public static func command(baseline: Double, occludedHeight: Double, pictureHeight: Double) -> PlayerCommand {
        let value = position(baseline: baseline, occludedHeight: occludedHeight, pictureHeight: pictureHeight)
        return .setSubtitleProperty(name: positionProperty, value: String(Int(value.rounded())))
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
