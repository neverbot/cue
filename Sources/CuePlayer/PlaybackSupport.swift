import Foundation

public enum LogRedactor {
    /// Signed stream URLs embed the requester's IP address; mpv prints them in error messages.
    public static func redact(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"(https?:)?//[^\s'"]*(googlevideo|youtube)\.com[^\s'"]*"#,
            with: "<url>",
            options: .regularExpression
        )
    }
}

public enum PlaybackTime {
    /// `m:ss` below an hour, `h:mm:ss` from an hour on. Negative and non-finite values show as `0:00`.
    public static func format(_ seconds: Double) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds.rounded(.down))) : 0
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

public enum StreamFreshness {
    /// Re-resolve slightly before the announced expiry, so a load or seek does not race it.
    public static let safetyMargin: TimeInterval = 120

    /// Streams without a known expiry are treated as fresh.
    public static func needsRefresh(expiresAt: Date?, now: Date, margin: TimeInterval = safetyMargin) -> Bool {
        guard let expiresAt else { return false }
        return now.addingTimeInterval(margin) >= expiresAt
    }
}
