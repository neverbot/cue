import Foundation

/// An 11-character YouTube video identifier.
public struct VideoID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public var description: String { rawValue }

    /// Path segments YouTube uses after `/embed/` that are not video ids.
    private static let reservedPathSegments: Set<String> = ["videoseries", "live_stream"]

    /// Validates a bare identifier: exactly 11 characters from `A-Z`, `a-z`, `0-9`, `-` and `_`.
    public init?(_ rawValue: String) {
        guard rawValue.count == 11,
              rawValue.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        self.rawValue = rawValue
    }

    /// Accepts a bare id or any common YouTube video URL form.
    /// When a URL carries both a `v` query parameter and a path id, the `v` parameter wins.
    public init?(url input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = VideoID(trimmed) {
            self = id
            return
        }
        let hasScheme = trimmed.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://", options: .regularExpression) != nil
        let absolute = hasScheme ? trimmed : "https://" + trimmed
        guard let components = URLComponents(string: absolute),
              let host = components.host?.lowercased() else { return nil }
        let pathParts = components.path.split(separator: "/").map(String.init)
        let isYouTubeHost = ["youtube.com", "youtube-nocookie.com"].contains { host == $0 || host.hasSuffix("." + $0) }

        var candidate: String?
        if host == "youtu.be" {
            candidate = pathParts.first
        } else if isYouTubeHost {
            if let v = components.queryItems?.first(where: { $0.name == "v" })?.value {
                candidate = v
            } else if pathParts.count >= 2, ["shorts", "embed", "live", "v"].contains(pathParts[0]) {
                candidate = pathParts[1]
            }
        }
        guard let candidate, !Self.reservedPathSegments.contains(candidate), let id = VideoID(candidate) else { return nil }
        self = id
    }
}
