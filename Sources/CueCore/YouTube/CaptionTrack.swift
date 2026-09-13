import Foundation

/// One caption track a video offers.
///
/// The `baseURL` is only usable when it came from Cue's own `/player` response: the same field taken from the watch
/// page's embedded player response answers 200 with an empty body.
public struct CaptionTrack: Sendable, Equatable, Identifiable {
    /// BCP-47 as YouTube writes it: `en`, `de-DE`, `es-419`.
    public let languageCode: String
    /// What YouTube calls the language, in the language of the request (`hl=en`).
    public let displayName: String
    /// A machine transcript rather than one somebody wrote.
    public let isAutomatic: Bool
    public let baseURL: URL

    public init(languageCode: String, displayName: String, isAutomatic: Bool, baseURL: URL) {
        self.languageCode = languageCode
        self.displayName = displayName
        self.isAutomatic = isAutomatic
        self.baseURL = baseURL
    }

    /// Stable within a video: a language usually appears twice, once written and once transcribed.
    public var id: String { isAutomatic ? "\(languageCode).asr" : languageCode }

    public var menuTitle: String { isAutomatic ? "\(displayName) (automatic)" : displayName }

    /// A file name stem for an export: `en`, `en-auto`.
    public var fileNameStem: String { isAutomatic ? "\(languageCode)-auto" : languageCode }

    public enum TimedTextFormat: String, Sendable, CaseIterable {
        /// Cue's own reader: timings and text, no styling.
        case json3
        case vtt
    }

    /// The track's URL asking for one format, replacing a format the URL already carries.
    public func url(format: TimedTextFormat) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return baseURL }
        var items = (components.queryItems ?? []).filter { $0.name != "fmt" }
        items.append(URLQueryItem(name: "fmt", value: format.rawValue))
        components.queryItems = items
        return components.url ?? baseURL
    }

    /// The tracks in a `/player` response, in the order YouTube listed them. Tracks without a URL or a language are
    /// dropped rather than shown as unusable rows.
    static func list(in captions: PlayerResponse.Captions?) -> [CaptionTrack] {
        (captions?.playerCaptionsTracklistRenderer?.captionTracks ?? []).compactMap { raw in
            guard let language = raw.languageCode, !language.isEmpty,
                  let string = raw.baseUrl, let url = URL(string: string)
            else { return nil }
            return CaptionTrack(
                languageCode: language,
                displayName: raw.name?.string ?? language,
                isAutomatic: raw.kind == "asr",
                baseURL: url
            )
        }
    }
}
