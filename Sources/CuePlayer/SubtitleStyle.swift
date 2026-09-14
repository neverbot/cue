import Foundation

/// How subtitles look. Every value maps to an mpv property, so the panel sets one thing and mpv redraws immediately;
/// nothing here is re-encoded, re-rendered or written to the subtitle file.
public struct SubtitleStyle: Equatable, Sendable {
    public enum Size: String, CaseIterable, Sendable {
        case small
        case medium
        case large
        case extraLarge

        public var scale: Double {
            switch self {
            case .small: 0.8
            case .medium: 1.0
            case .large: 1.4
            case .extraLarge: 1.8
            }
        }

        public var title: String {
            switch self {
            case .small: "Small"
            case .medium: "Medium"
            case .large: "Large"
            case .extraLarge: "Extra Large"
            }
        }
    }

    public enum Colour: String, CaseIterable, Sendable {
        case white
        case yellow

        /// mpv's `#AARRGGBB`.
        public var value: String {
            switch self {
            case .white: "#FFFFFFFF"
            case .yellow: "#FFFFF200"
            }
        }

        public var title: String {
            switch self {
            case .white: "White"
            case .yellow: "Yellow"
            }
        }
    }

    public var size: Size = .medium
    public var colour: Colour = .white
    /// An outline around the glyphs, in mpv's units. Zero turns it off.
    public var borderSize: Double = 3
    /// A translucent box behind the text, for subtitles over bright video.
    ///
    /// This drives mpv's border *style*, not only its back colour. `sub-back-color` is the colour the box is painted
    /// in, and nothing paints it while the border style is the default outline-and-shadow: setting the colour alone
    /// changed a value that nothing read, which is why the checkbox appeared to do nothing at all.
    public var hasBackgroundBox = false
    /// Distance from the bottom of the frame, 0–150 in mpv's units; 100 is the default position.
    public var position: Double = 100

    public init() {}

    /// The properties to set, in a fixed order so the panel and the tests agree.
    public var properties: [MPVOption] {
        [
            MPVOption("sub-scale", String(format: "%.1f", size.scale)),
            MPVOption("sub-color", colour.value),
            MPVOption("sub-border-size", String(format: "%.1f", borderSize)),
            MPVOption("sub-back-color", hasBackgroundBox ? "#80000000" : "#00000000"),
            // The two names this build's `border-style` accepts alongside `opaque-box`, which Cue does not offer:
            // `background-box` fills one rectangle behind the whole line in `sub-back-color`, and
            // `outline-and-shadow` is mpv's own default, the outlined text the checkbox returns to.
            MPVOption("sub-border-style", hasBackgroundBox ? "background-box" : "outline-and-shadow"),
            MPVOption(SubtitleLift.positionProperty, String(Int(position.rounded()))),
        ]
    }

    /// The same properties as commands, for handing straight to the player.
    public var commands: [PlayerCommand] {
        properties.map { .setSubtitleProperty(name: $0.name, value: $0.value) }
    }
}
