import CueCore
import Foundation

@main
struct CueResolve {
    static let usage = "usage: cue-resolve <youtube-url-or-id>\n"

    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["-h"] || arguments == ["--help"] {
            print(usage, terminator: "")
            exit(0)
        }
        guard arguments.count == 1, let videoID = VideoID(url: arguments[0]) else {
            FileHandle.standardError.write(Data(usage.utf8))
            exit(2)
        }
        if Extractor.bundledSolver == nil {
            FileHandle.standardError.write(Data("warning: challenge solver scripts not found next to the executable; videos that need them will fail\n".utf8))
        }

        let started = Date()
        do {
            let resolution = try await Extractor().resolve(videoID)
            let video = resolution.selection.video
            let audio = resolution.selection.audio
            print("title:      \(resolution.title)")
            print("author:     \(resolution.author ?? "-")")
            print("duration:   \(resolution.duration.map { "\(Int($0)) s" } ?? "-")")
            print("formats:    \(resolution.formats.count), hls: \(resolution.hlsManifestURL != nil), captions: \(resolution.captionTrackCount)")
            let shortSide = [video.width, video.height].compactMap { $0 }.min()
            print("selected:   video itag \(video.itag) \(video.codec) \(shortSide.map { "\($0)p" } ?? "-") | audio itag \(audio.itag) \(audio.codec)")
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
