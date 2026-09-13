import Foundation

/// YouTube's storyboard specification: the sheets of thumbnails behind the seek bar's preview.
///
/// The string is `<base>|<level>|<level>…`. The base carries a `$L` placeholder for the level and `$N` for the sheet
/// name; each level is `width#height#frameCount#columns#rows#intervalMilliseconds#nameTemplate#signature`, where
/// `frameCount` counts the frames across *every* sheet of that level and `columns × rows` is how many fit on one.
public struct StoryboardSpec: Sendable, Equatable {
    public struct Level: Sendable, Equatable {
        public let index: Int
        public let width: Int
        public let height: Int
        public let frameCount: Int
        public let columns: Int
        public let rows: Int
        /// Zero on the overview level, whose frames span the whole video instead of a fixed interval.
        public let intervalMilliseconds: Int
        /// The sheet's file name; a `$M` in it stands for the sheet index.
        public let nameTemplate: String
        /// The `sigh` query value, prefix included. Without the `rs$` prefix YouTube answers 403.
        public let signature: String

        public var framesPerSheet: Int { max(1, columns * rows) }

        public var sheetCount: Int {
            max(1, Int((Double(frameCount) / Double(framesPerSheet)).rounded(.up)))
        }

        /// Seconds between consecutive frames, or nil when neither the spec nor the duration says.
        public func interval(duration: Double?) -> Double? {
            if intervalMilliseconds > 0 { return Double(intervalMilliseconds) / 1000 }
            guard let duration, duration > 0, frameCount > 0 else { return nil }
            return duration / Double(frameCount)
        }
    }

    /// One frame's place: which sheet to fetch and which tile of it to crop.
    public struct Frame: Sendable, Equatable {
        public let url: URL
        public let sheet: Int
        public let column: Int
        public let row: Int
        public let width: Int
        public let height: Int

        /// The tile's top-left corner inside the sheet image, in pixels.
        public var originX: Int { column * width }
        public var originY: Int { row * height }
    }

    /// The base URL, `$L` and `$N` still in place.
    public let template: String
    public let levels: [Level]

    /// Nil when the string carries no usable level.
    public init?(_ spec: String) {
        var parts = spec.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 1 else { return nil }
        let template = parts.removeFirst()
        guard !template.isEmpty else { return nil }
        let parsed = parts.compactMap { Level(fields: $0) }
        guard !parsed.isEmpty else { return nil }
        self.template = template
        self.levels = parsed.enumerated().map { $0.element.reindexed(to: $0.offset) }
    }

    /// The largest level offered. Cue's client is served three (up to 160×90); the web client sees a fourth.
    public var bestLevel: Level? {
        levels.max { $0.width < $1.width }
    }

    public func sheetURL(level: Level, sheet: Int) -> URL? {
        let name = level.nameTemplate.replacingOccurrences(of: "$M", with: String(max(0, sheet)))
        let path = template
            .replacingOccurrences(of: "$L", with: String(level.index))
            .replacingOccurrences(of: "$N", with: name)
        return URL(string: path + (path.contains("?") ? "&" : "?") + "sigh=" + level.signature)
    }

    /// The frame covering `seconds`, clamped into the video at both ends.
    public func frame(at seconds: Double, duration: Double?, level: Level) -> Frame? {
        guard let interval = level.interval(duration: duration), interval > 0, level.frameCount > 0 else { return nil }
        let raw = seconds.isFinite ? Int((seconds / interval).rounded(.down)) : 0
        let index = min(max(raw, 0), level.frameCount - 1)
        let sheet = index / level.framesPerSheet
        let offset = index % level.framesPerSheet
        guard let url = sheetURL(level: level, sheet: sheet) else { return nil }
        return Frame(
            url: url,
            sheet: sheet,
            column: offset % level.columns,
            row: offset / level.columns,
            width: level.width,
            height: level.height
        )
    }
}

extension StoryboardSpec.Level {
    /// Parses one `|`-separated level; the index is assigned afterwards, over the levels that survive parsing.
    fileprivate init?(fields: String) {
        let parts = fields.split(separator: "#", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 8,
              let width = Int(parts[0]), let height = Int(parts[1]), let frameCount = Int(parts[2]),
              let columns = Int(parts[3]), let rows = Int(parts[4]), let interval = Int(parts[5]),
              width > 0, height > 0, frameCount > 0, columns > 0, rows > 0
        else { return nil }
        self.init(
            index: 0,
            width: width,
            height: height,
            frameCount: frameCount,
            columns: columns,
            rows: rows,
            intervalMilliseconds: max(0, interval),
            nameTemplate: parts[6],
            signature: parts[7]
        )
    }

    fileprivate func reindexed(to index: Int) -> Self {
        StoryboardSpec.Level(
            index: index,
            width: width,
            height: height,
            frameCount: frameCount,
            columns: columns,
            rows: rows,
            intervalMilliseconds: intervalMilliseconds,
            nameTemplate: nameTemplate,
            signature: signature
        )
    }
}
