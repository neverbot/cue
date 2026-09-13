import Foundation
import os

private let logger = Logger(subsystem: "com.neverbot.cue", category: "extraction")

/// Reads chapter markers out of the watch page Cue already downloads. The `/player` response has none: no
/// `playerOverlays`, no chapters anywhere in it. Doing this here costs no extra request.
enum WatchPageChapters {
    /// The marker lists, in the order Cue prefers them: what the author wrote, then what YouTube guessed.
    static let preferredKeys = ["DESCRIPTION_CHAPTERS", "AUTO_CHAPTERS"]

    static func chapters(inHTML html: String, duration: Double?) -> [Chapter] {
        guard let data = WatchPage.initialData(in: html) else { return [] }
        let initial: InitialData
        do {
            initial = try JSONDecoder().decode(InitialData.self, from: data)
        } catch {
            // The watch page is the sensitive response: it carries visitorData and the owner's session. A decoding
            // failure describes what was being read, and a corrupted-data error can quote the bytes around it, so
            // this stays private like every other error raised over the owner's own data.
            logger.error("Unreadable watch page data: \(String(describing: error), privacy: .private)")
            return []
        }
        let maps = initial.playerOverlays?.playerOverlayRenderer?.decoratedPlayerBarRenderer?
            .decoratedPlayerBarRenderer?.playerBar?.multiMarkersPlayerBarRenderer?.markersMap ?? []
        let chosen = preferredKeys.lazy.compactMap { key in maps.first { $0.key == key } }.first
            ?? maps.first { !($0.value?.chapters ?? []).isEmpty }
        let chapters = (chosen?.value?.chapters ?? []).compactMap { entry -> Chapter? in
            guard let renderer = entry.chapterRenderer,
                  let title = renderer.title?.string,
                  let start = renderer.timeRangeStartMillis?.value
            else { return nil }
            return Chapter(title: title, start: start / 1000)
        }
        return Chapter.closing(chapters, duration: duration)
    }

    // MARK: - The subset of ytInitialData that carries markers

    private struct InitialData: Decodable {
        let playerOverlays: PlayerOverlays?
    }

    private struct PlayerOverlays: Decodable {
        let playerOverlayRenderer: OverlayRenderer?
    }

    private struct OverlayRenderer: Decodable {
        let decoratedPlayerBarRenderer: DecoratedOuter?
    }

    /// The renderer name really is repeated inside itself in the response.
    private struct DecoratedOuter: Decodable {
        let decoratedPlayerBarRenderer: DecoratedInner?
    }

    private struct DecoratedInner: Decodable {
        let playerBar: PlayerBar?
    }

    private struct PlayerBar: Decodable {
        let multiMarkersPlayerBarRenderer: MultiMarkers?
    }

    private struct MultiMarkers: Decodable {
        let markersMap: [MarkerMap]?
    }

    private struct MarkerMap: Decodable {
        let key: String?
        let value: MarkerValue?
    }

    private struct MarkerValue: Decodable {
        let chapters: [ChapterEntry]?
    }

    private struct ChapterEntry: Decodable {
        let chapterRenderer: ChapterRenderer?
    }

    private struct ChapterRenderer: Decodable {
        let title: PlayerResponse.Text?
        let timeRangeStartMillis: LenientNumber?
    }

    /// InnerTube writes the same field as a number here and a string there.
    private struct LenientNumber: Decodable {
        let value: Double?

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                value = number
            } else {
                value = Double(try container.decode(String.self))
            }
        }
    }
}
