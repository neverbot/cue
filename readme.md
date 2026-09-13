# Cue

**Your YouTube "watch later" queue, in a native macOS player. No ads, no browser tabs, no fans spinning up.**

Cue keeps a personal queue of the YouTube videos you want to watch and plays them in a fast, native player built for the Mac. It aims for the polish of the best Mac media players: a clean window that stays out of the way, a sidebar with everything still pending, and playback that uses the hardware decoder in your Mac instead of a browser tab.

> **Status: early development.** The extraction core, the command-line tool, the player, the queue and the player's chrome — chapters, subtitles, scrubbing previews and a mini player — are all built and covered by the test suite. What is still missing is a pass with human eyes on the interface, and a signed release you can download. See [Roadmap](#roadmap).

## Why Cue

- **No ads, ever.** Cue does not use the embedded YouTube player. It resolves the video streams itself and plays them natively.
- **Light on your Mac.** Hardware decoding is the default. Cue picks a stream your chip decodes in silicon: AV1 on Macs that support it, H.264, or VP9 where VideoToolbox decodes it. Software decoding is only a last resort for videos that offer nothing else.
- **Native and self-contained.** One app with everything inside. There is nothing to install at first launch, and no bundled Python or JavaScript runtime. The little JavaScript YouTube requires runs in macOS's own JavaScriptCore.
- **Your queue, your data.** No account and no sign-in. Your list lives on your Mac and can be imported and exported.
- **Open source.** MIT licensed, and built entirely from the command line.

## Privacy

Cue talks to YouTube, and to nothing else. No analytics, no crash reporting, no third-party metadata or segment
service, no account, no sync. A feature that would need an outside service is left out of the app rather than added
behind an opt-in switch. Everything Cue fetches — the watch page, the player response, storyboard tiles, caption
tracks — comes from YouTube straight to your Mac, and nothing about what you watch goes anywhere else.

## Features

| Feature | Status |
|---|---|
| Resolve playable streams natively (no embed player, no external tools) | Available in `CueCore` |
| Hardware-first format selection (AV1, H.264 or VP9 in hardware; software VP9/AV1 only as a fallback; AAC audio) | Available in `CueCore` |
| `cue-resolve` command-line tool | Available |
| Native player (libmpv), keyboard controls, resume position | Available in `Cue.app` (build from source) |
| Queue sidebar with counter and total pending time; paste, drag & drop, `cue://` links | Available in `Cue.app` (manual checks pending) |
| Import and export of the queue | Available in `Cue.app` (manual checks pending) |
| Drawn on-screen controls with chapter marks on the seek bar, and a title bar that fades with them | Available in `Cue.app` (manual checks pending) |
| Thumbnail previews while scrubbing, from YouTube's own storyboard sheets | Available in `Cue.app` (manual checks pending) |
| A chapters panel built from the video's own markers, or from the timestamps in its description | Available in `Cue.app` (manual checks pending) |
| A subtitles panel: pick a track, size and colour it, shift its timing, and export it as SRT or VTT | Available in `Cue.app` (manual checks pending) |
| A mini player: a small always-on-top window that keeps playing, with no reload and no second stream | Available in `Cue.app` (manual checks pending) |
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
scripts/fetch-libmpv.sh   # downloads MPVKit's LGPL libmpv archives (about 330 MB, cached in vendor/cache) and links libmpv
                          # unpacked intermediates are pruned automatically after linking; pass --keep-intermediates to keep them
swift build
```

### Building and running the app

```sh
scripts/make-app.sh                                                     # builds and signs dist/Cue.app (ad-hoc)
open dist/Cue.app --args "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

You can also start Cue without arguments and paste a YouTube link with ⌘V.

| Key | Action |
|---|---|
| Space | Play or pause |
| ← / → | Seek 5 seconds |
| ↑ / ↓ | Volume |
| F | Full screen |
| M | Mute |
| ⌘W | Close |

Cue remembers where you stopped each video and resumes there next time.

### Running the tests

```sh
scripts/test.sh                            # offline test suite
scripts/test.sh --filter ExtractorTests    # a subset
CUE_LIVE_TESTS=1 scripts/test.sh           # also run tests that contact YouTube
CUE_MPV_TESTS=1 scripts/test.sh            # also play a synthetic clip through libmpv
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
  CMpv/                    system module for libmpv's C API
  CueMPV/                  Swift wrapper around libmpv (core and render API)
  CuePlayer/               player logic: state, commands, resume positions, window sizing
  Cue/                     the macOS app (AppKit, OpenGL video layer)
Tests/                     Swift Testing suites, sanitized fixtures and synthetic media
packaging/                 Info.plist, entitlements and license texts for the app bundle
scripts/                   test runner, libmpv fetch, app bundle and fixture scripts
```

## Roadmap

1. **Foundation and native extraction.** Done: `CueCore` and `cue-resolve`.
2. **Player core.** Available: `Cue.app` plays with libmpv and hardware decoding, with on-screen controls, keyboard shortcuts and resume positions (manual checks pending).
3. **Queue.** Available: a persistent SQLite queue with list, thumbnail and compact views, a counter and the pending time, adding by paste, drag and drop or `cue://add` links, import and export, and watched state (manual checks pending).
4. **Polish.** Available: restyled on-screen controls with a title bar that fades with them, thumbnail previews while scrubbing, a chapters panel, a subtitles panel with SRT/VTT export, and an always-on-top mini player (manual checks pending).
5. **Browser integration.** Bookmarklet and extensions for Firefox and Chrome.
6. **Subscriptions.** Channel feeds and new-video notifications.
7. **Casting.** Research first: AirPlay, Chromecast, DLNA.
8. **Distribution.** Developer ID signing, notarization, automatic updates.

## The queue

Cue keeps its queue in SQLite at `~/Library/Application Support/Cue/queue.sqlite`, with schema migrations, beside the
player's own data. The file is created readable only by you. Resume positions live in the same database; a
`resume-positions.json` left by an earlier version is imported once at launch and then left alone.

The sidebar (⌃⌘S to show or hide it, ⌃⌘M to cycle its density, ⌃⌘O to float it over the video instead of pushing it
aside) lists what is left to watch with a counter and the total pending time. Videos whose length is not known yet are
not in that total, which is why it can read `3 h 21 min+`.

Add videos by pasting links (⌘V takes as many as the clipboard holds), by dropping links onto the sidebar, or with a
`cue://add?url=<video URL>` link from a browser or a script. Adding the same video twice never duplicates it. ⇧⌘N
plays the next pending video and ⇧⌘D marks the current one watched; Queue ▸ Play Next Automatically decides whether
finishing a video starts the next one. A video is marked watched on its own when playback reaches the last 20 seconds.

Thumbnails are YouTube's public still images, cached in `~/Library/Caches/Cue/thumbnails` by video id and capped at
32 MB. Deleting that folder costs nothing.

### Import and export

File ▸ Import Queue… reads three formats, and File ▸ Export Queue… writes them; the file extension decides which
(`.txt`, `.json`, `.csv`), and an imported file is sniffed if its extension says nothing. Importing is idempotent:
videos already queued are left as they are, and the summary says how many were added, skipped and unreadable.

- **URL list** (`.txt`): one video URL or id per line. Lines starting with `#` are comments.
- **Cue JSON** (`.json`): `{"version": 1, "items": [{"videoID", "title", "author", "duration", "addedAt",
  "watchedAt"}]}`. This is the format that round-trips everything, watched state included.
- **CSV** (`.csv`): comma separated, `"` quoted. A Google Takeout playlist export
  (`Video ID,Playlist Video Creation Timestamp`) imports as it is. Column names are matched case-insensitively:

  | Field | Accepted column names |
  |---|---|
  | video id or URL | `video id`, `videoid`, `id`, `video url`, `url`, `video` |
  | title | `title`, `video title` |
  | author | `author`, `channel`, `channel title` |
  | duration in seconds | `duration`, `duration seconds` |
  | added | `playlist video creation timestamp`, `video creation timestamp`, `timestamp`, `added`, `added timestamp` |
  | watched | `watched`, `watched timestamp` |

  A CSV whose header names none of the video columns is read as a URL list instead, and a file without a header is read
  as ids in the first column. A quoted field keeps its spaces; an unquoted one is trimmed.

## Chapters, subtitles and the mini player

Chapters come from the video itself — the markers YouTube serves with the watch page, or, when there are none, the
timestamps in the description. Nothing is fetched from anywhere else, and nothing is guessed.

Subtitles are the caption tracks the video offers. Choosing one downloads it, writes it as WebVTT into a private
temporary directory and hands that file to the player, so a subtitle cannot expire in the middle of a video the way a
stream URL can. Size, colour, an optional background box and the timing offset (`z` and `x`, or the panel's slider)
apply immediately. Export writes SubRip (`.srt`) or WebVTT (`.vtt`) from the same text that is on screen.

The mini player (⌘⇧M) moves the video into a small floating window that stays above other apps. It is the same player:
the stream is not re-resolved, playback does not pause, and closing the small window brings the video back.

| Key | Does |
|---|---|
| `c` | Chapters panel |
| `s` | Subtitles panel |
| `⌃⌘C` | Chapters panel (menu) |
| `⌃⌘U` | Subtitles panel (menu) |
| `⌥→` / `⌥←` | Next / previous chapter |
| `z` / `x` | Subtitle delay −0.1 s / +0.1 s |
| `⌘⇧M` | Mini player |

## Contributing

Issues and pull requests are welcome. A few ground rules keep the project healthy:

- **Keep it native and self-contained.** No Xcode-only artefacts, no runtime downloads, no bundled interpreters.
- **Licensing.** Dependencies must be MIT-compatible or LGPL. Do not copy code from GPL projects.
- **Tests stay offline by default.** Fixtures must be sanitized: no IP addresses, session tokens or personal data. Use only the public test videos already in the suite (`dQw4w9WgXcQ`, `jNQXAC9IVRw`). For invalid ids, use obviously synthetic values such as `123456789_`.
- **Commits.** Conventional Commits, one line each.

When YouTube changes something and extraction breaks, the usual places to look are the client definitions in yt-dlp (`yt_dlp/extractor/youtube/_base.py`) and new releases of [yt-dlp/ejs](https://github.com/yt-dlp/ejs).

## License

Cue is released under the [MIT License](license.md).

It bundles third-party code under its own licenses, notably the yt-dlp EJS solver scripts (The Unlicense), which include meriyah (ISC) and astring (MIT), and libmpv with FFmpeg as a replaceable LGPL shared library. See [third-party-licenses.md](third-party-licenses.md).

## Disclaimer

Cue is an independent project. It is not affiliated with, endorsed by or sponsored by YouTube or Google. It is meant for personal viewing of content you are allowed to watch. You are responsible for complying with YouTube's Terms of Service and with the rights of content creators.
