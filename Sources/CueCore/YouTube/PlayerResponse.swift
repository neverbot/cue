import Foundation

/// Subset of the InnerTube `/player` JSON that Cue uses.
struct PlayerResponse: Decodable, Sendable {
    struct PlayabilityStatus: Decodable, Sendable {
        let status: String
        let reason: String?
    }

    struct VideoDetails: Decodable, Sendable {
        let videoId: String
        let title: String
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
        let itag: Int
        let url: String?
        let signatureCipher: String?
        let mimeType: String
        let bitrate: Int?
        let width: Int?
        let height: Int?
        let fps: Int?
        let contentLength: String?
        let qualityLabel: String?
    }

    struct Captions: Decodable, Sendable {
        let playerCaptionsTracklistRenderer: Tracklist?
    }

    struct Tracklist: Decodable, Sendable {
        let captionTracks: [CaptionTrack]?
    }

    struct CaptionTrack: Decodable, Sendable {
        let baseUrl: String
        let languageCode: String
        let kind: String?
    }

    struct Storyboards: Decodable, Sendable {
        let playerStoryboardSpecRenderer: Spec?
    }

    struct Spec: Decodable, Sendable {
        let spec: String
    }

    let playabilityStatus: PlayabilityStatus
    let videoDetails: VideoDetails?
    let streamingData: StreamingData?
    let captions: Captions?
    let storyboards: Storyboards?
}
