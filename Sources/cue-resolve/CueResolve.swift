import CueCore
import Foundation

@main
struct CueResolve {
    static func main() async {
        guard let input = CommandLine.arguments.dropFirst().first, let videoID = VideoID(url: input) else {
            FileHandle.standardError.write(Data("usage: cue-resolve <youtube-url-or-id>\n".utf8))
            exit(2)
        }

        let started = Date()
        do {
            let resolution = try await Extractor().resolve(videoID)
            let video = resolution.selection.video
            let audio = resolution.selection.audio
            print("title:      \(resolution.title)")
            print("author:     \(resolution.author ?? "-")")
            print("duration:   \(Int(resolution.duration ?? 0)) s")
            print("formats:    \(resolution.formats.count), hls: \(resolution.hlsManifestURL != nil), captions: \(resolution.captionTrackCount)")
            print("selected:   video itag \(video.itag) \(video.codec) \(video.height ?? 0)p | audio itag \(audio.itag) \(audio.codec)")
            print("user-agent: \(resolution.userAgent)")
            print("video:      \(video.url.absoluteString)")
            print("audio:      \(audio.url.absoluteString)")
            print(String(format: "resolved in %.2f s", Date().timeIntervalSince(started)))
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            FileHandle.standardError.write(Data("error: \(message)\n".utf8))
            exit(1)
        }
    }
}
