import Foundation

/// Subset of the InnerTube `/player` JSON that Cue uses.
struct PlayerResponse: Decodable, Sendable {
    struct PlayabilityStatus: Decodable, Sendable {
        let status: String
        let reason: String?
    }

    struct VideoDetails: Decodable, Sendable {
        let videoId: String?
        let title: String?
        let author: String?
        let channelId: String?
        let lengthSeconds: String?
        let shortDescription: String?
    }

    struct StreamingData: Decodable, Sendable {
        let adaptiveFormats: [RawFormat]?
        let hlsManifestUrl: String?
        let expiresInSeconds: String?
    }

    struct RawFormat: Decodable, Sendable {
        /// The language of one audio format, present only on videos that offer dubs. Field names are YouTube's own.
        struct AudioTrack: Decodable, Sendable {
            /// `en.4`, `es-ES.3`: the language code, a dot, and YouTube's own index for the track.
            let id: String?
            let displayName: String?
            /// True on the track YouTube plays by default — the original soundtrack.
            let audioIsDefault: Bool?
        }

        let itag: Int
        let url: String?
        let signatureCipher: String?
        let mimeType: String?
        let bitrate: Int?
        let width: Int?
        let height: Int?
        let fps: Int?
        let contentLength: String?
        let qualityLabel: String?
        /// Absent on every format of a single-language video, and on every video format.
        let audioTrack: AudioTrack?
    }

    struct Captions: Decodable, Sendable {
        let playerCaptionsTracklistRenderer: Tracklist?
    }

    struct Tracklist: Decodable, Sendable {
        let captionTracks: [CaptionTrack]?
    }

    struct CaptionTrack: Decodable, Sendable {
        let baseUrl: String?
        let languageCode: String?
        let kind: String?
        let name: Text?
    }

    /// InnerTube's text node: either one string or a list of runs.
    struct Text: Decodable, Sendable {
        let simpleText: String?
        let runs: [Run]?

        struct Run: Decodable, Sendable {
            let text: String?
        }

        var string: String? {
            if let simpleText, !simpleText.isEmpty { return simpleText }
            let joined = (runs ?? []).compactMap(\.text).joined()
            return joined.isEmpty ? nil : joined
        }
    }

    struct Storyboards: Decodable, Sendable {
        let playerStoryboardSpecRenderer: Spec?
    }

    struct Spec: Decodable, Sendable {
        let spec: String?
    }

    let playabilityStatus: PlayabilityStatus
    let videoDetails: VideoDetails?
    let streamingData: StreamingData?
    let captions: Captions?
    let storyboards: Storyboards?
}
