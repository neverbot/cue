# Cue

**Your YouTube "watch later" queue, in a native macOS player. No ads, no browser tabs, no fans spinning up.**

Cue keeps a personal queue of the YouTube videos you want to watch and plays them in a fast, native player built for the Mac. It aims for the polish of the best Mac media players: a clean window that stays out of the way, a sidebar with everything still pending, and playback that uses the hardware decoder in your Mac instead of a browser tab.

> **Status: early development.** The native extraction core and a command-line tool work today. The player, the queue and the app itself are next. See [Roadmap](#roadmap).

## Why Cue

- **No ads, ever.** Cue does not use the embedded YouTube player. It resolves the video streams itself and plays them natively.
- **Light on your Mac.** Hardware decoding is the default. Cue picks a stream your chip decodes in silicon: AV1 on Macs that support it, H.264, or VP9 where VideoToolbox decodes it. Software decoding is only a last resort for videos that offer nothing else.
- **Native and self-contained.** One app with everything inside. There is nothing to install at first launch, and no bundled Python or JavaScript runtime. The little JavaScript YouTube requires runs in macOS's own JavaScriptCore.
- **Your queue, your data.** No account and no sign-in. Your list lives on your Mac and can be imported and exported.
- **Open source.** MIT licensed, and built entirely from the command line.

## Features

| Feature | Status |
|---|---|
| Resolve playable streams natively (no embed player, no external tools) | Available in `CueCore` |
| Hardware-first format selection (AV1, H.264 or VP9 in hardware; software VP9/AV1 only as a fallback; AAC audio) | Available in `CueCore` |
| `cue-resolve` command-line tool | Available |
| Native player (libmpv), keyboard controls, resume position | Planned |
| Queue sidebar with counter and total pending time; paste, drag & drop, `cue://` links | Planned |
| Import and export of the queue | Planned |
| Chapters, subtitles, seek-bar previews, mini player | Planned |
| Browser extension and bookmarklet ("send this tab to Cue") | Planned |
| Channel subscriptions with new-video alerts | Planned |

## Requirements

- macOS 14 Sonoma or later.
- To build from source: Apple Command Line Tools with Swift 6 (`xcode-select --install`). Xcode is not needed.

There is no downloadable app yet. Signed releases will be published once the player is usable.

## Try it: `cue-resolve`

`cue-resolve` shows what Cue's extraction core does. Give it a YouTube URL or video id, and it prints the video details and the stream URLs it would play.

```console
$ swift run -q cue-resolve "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
title:      Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)
author:     Rick Astley
duration:   213 s
formats:    27, hls: true, captions: 6
expires:    in 358 min
selected:   video itag 137 avc1 1080p | audio itag 140 mp4a
user-agent: Mozilla/5.0 (…)
video:      https://…googlevideo.com/videoplayback?…
audio:      https://…googlevideo.com/videoplayback?…
resolved in 0.92 s
```

Stream URLs are tied to your IP address and expire after a few hours. To check that they play, pass the printed user agent to `ffprobe` or `mpv`:

```sh
OUT=$(swift run -q cue-resolve dQw4w9WgXcQ)
UA=$(printf '%s\n' "$OUT" | sed -n 's/^user-agent: *//p')
URL=$(printf '%s\n' "$OUT" | sed -n 's/^video: *//p')
ffprobe -v error -user_agent "$UA" -show_entries stream=codec_name,width,height "$URL"
```

Exit codes: `0` on success, `1` when the video cannot be resolved (the reason is printed to stderr), and `2` on invalid usage.

## Building from source

Everything builds with the Swift toolchain from Apple's Command Line Tools. There is no Xcode project.

```sh
git clone https://github.com/neverbot/cue.git
cd cue
swift build
```

### Running the tests

```sh
scripts/test.sh                            # offline test suite
scripts/test.sh --filter ExtractorTests    # a subset
CUE_LIVE_TESTS=1 scripts/test.sh           # also run tests that contact YouTube
```

Use `scripts/test.sh` rather than `swift test`. On a machine with only the Command Line Tools installed, SwiftPM does not find the Swift Testing framework on its own. The script adds the missing framework search paths and forwards any arguments to `swift test`.

The default suite runs offline against sanitized fixtures. The live tests resolve two public videos and check that their streams answer. They depend on YouTube's current behaviour and are opt-in for that reason.

## How it works

YouTube does not offer a public API for playable streams. Cue follows the same path a YouTube client does:

1. **Parse the input.** `VideoID` accepts video ids and the common URL forms (`watch`, `youtu.be`, `shorts`, `embed`, `live`).
2. **Ask YouTube for the player response.** `WatchPage` reads a visitor token from the watch page. `InnerTube` then requests `/youtubei/v1/player` with a client profile that currently returns directly playable formats.
3. **Solve playback challenges when needed.** Some stream URLs carry obfuscated parameters (`n` and signature) that must be transformed by YouTube's own player JavaScript. `PlayerScript` locates the current player. `ChallengeSolver` runs yt-dlp's EJS solver scripts in macOS's JavaScriptCore and caches the preprocessed player.
4. **Pick the streams.** `FormatSelector` chooses the best video your Mac decodes in hardware (up to 1080p by default) and the best AAC audio track. Only when a video offers no hardware-friendly stream does it fall back to software decoding (VP9 up to 1080p, then AV1 up to 720p), and it reports which way it went.

The result is a `Resolution`: title, author, duration, the selected video and audio streams, and the user agent the streams must be requested with.

### Project layout

```text
Package.swift
Sources/
  CueCore/                 extraction library
    YouTube/               VideoID, WatchPage, InnerTube, PlayerResponse,
                           StreamFormat, FormatSelector, Extractor
    Challenges/            PlayerScript, ChallengeSolver
    Networking/            HTTPClient abstraction over URLSession
    Resources/ejs/         vendored yt-dlp EJS solver scripts
  cue-resolve/             command-line tool
Tests/CueCoreTests/        Swift Testing suites and sanitized fixtures
scripts/test.sh            test runner for Command Line Tools-only machines
```

## Roadmap

1. **Foundation and native extraction.** Done: `CueCore` and `cue-resolve`.
2. **Player core.** The `.app` bundle, libmpv playback with hardware decoding, on-screen controls, keyboard shortcuts, resume position.
3. **Queue.** Persistent queue with list and thumbnail views, counter and pending time, adding by paste or drag & drop or `cue://` links, import and export.
4. **Polish.** On-screen controller styles, seek-bar previews, chapters, subtitles, mini player.
5. **Browser integration.** Bookmarklet and extensions for Firefox and Chrome.
6. **Subscriptions.** Channel feeds and new-video notifications.
7. **Casting.** Research first: AirPlay, Chromecast, DLNA.
8. **Distribution.** Developer ID signing, notarization, automatic updates.

## Contributing

Issues and pull requests are welcome. A few ground rules keep the project healthy:

- **Keep it native and self-contained.** No Xcode-only artefacts, no runtime downloads, no bundled interpreters.
- **Licensing.** Dependencies must be MIT-compatible or LGPL. Do not copy code from GPL projects.
- **Tests stay offline by default.** Fixtures must be sanitized: no IP addresses, session tokens or personal data. Use only the public test videos already in the suite (`dQw4w9WgXcQ`, `jNQXAC9IVRw`). For invalid ids, use obviously synthetic values such as `123456789_`.
- **Commits.** Conventional Commits, one line each.

When YouTube changes something and extraction breaks, the usual places to look are the client definitions in yt-dlp (`yt_dlp/extractor/youtube/_base.py`) and new releases of [yt-dlp/ejs](https://github.com/yt-dlp/ejs).

## License

Cue is released under the [MIT License](license.md).

It bundles third-party code under its own licenses, notably the yt-dlp EJS solver scripts (The Unlicense), which include meriyah (ISC) and astring (MIT). See [third-party-licenses.md](third-party-licenses.md).

## Disclaimer

Cue is an independent project. It is not affiliated with, endorsed by or sponsored by YouTube or Google. It is meant for personal viewing of content you are allowed to watch. You are responsible for complying with YouTube's Terms of Service and with the rights of content creators.
