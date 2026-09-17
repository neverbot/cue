# Cue

**Your YouTube "watch later" queue, in a native macOS player. No ads, no browser tabs, no fans spinning up.**

Cue keeps a personal queue of the YouTube videos you want to watch and plays them in a fast, native player built for the Mac. It aims for the polish of the best Mac media players: a clean window that stays out of the way, a sidebar with everything still pending, and playback that uses the hardware decoder in your Mac instead of a browser tab.

> **Cue is built from source**, with Apple's Command Line Tools and two commands. See
> [Building from source](#building-from-source).

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

- **Native stream resolution.** No embed player, no external tools: Cue asks YouTube for the streams itself.
- **Hardware-first format selection.** AV1, H.264 or VP9 decoded in silicon, with AAC audio; software decoding only
  when a video offers nothing better.
- **A native player** on libmpv, with keyboard control, resume positions, and a spinner whenever it is finding,
  opening or buffering a stream rather than a black window.
- **Made for slow connections**: the seek bar shows how far the video has loaded, and a paused video keeps loading —
  up to about twenty minutes of 1080p, cached on disk in `~/Library/Caches/Cue/stream-cache` rather than in memory,
  and deleted as it is written so nothing is left behind.
- **A queue sidebar** in three densities, beside the video or floating over it, with a counter, watched marks and a
  tinted row for the video playing now.
- **Adding videos** by paste, drag and drop, or a `cue://add` link — and playing one the moment it is added.
- **Import and export** of the queue as a URL list, JSON or Takeout-style CSV.
- **Drawn on-screen controls** with chapter marks on the seek bar and a title bar that fades with them.
- **Thumbnail previews while scrubbing**, from YouTube's own storyboard sheets.
- **A trailing inspector** with chapters, subtitles and audio languages, each on its own page.
- **Chapters** from the video's own markers, or from the timestamps in its description.
- **Subtitles**: pick a track, size and colour it, shift its timing, export it as SRT or WebVTT.
- **Audio languages**: the original soundtrack of a dubbed video by default, switchable without reloading.
- **A mini player**: a small always-on-top window that keeps playing, with no reload and no second stream.
- **A settings window** for appearance, automatic playback, the sidebar, the thumbnail cache and the queue.
- **An About window** with the version, the author, and the licenses of everything bundled.
- **A bookmarklet** that sends the YouTube page you are on to Cue, installed from the app itself.
- **`cue-resolve`**, a command-line tool that prints what the extraction core resolves.

## Requirements

- macOS 14 Sonoma or later.
- To build from source: Apple Command Line Tools with Swift 6 (`xcode-select --install`). Xcode is not needed.

The app you build is signed ad-hoc, for your own machine.

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
scripts/build.sh          # builds with the build engine pinned; forwards any `swift build` arguments
```

**The first build needs network twice**: once for libmpv above, and once for GRDB, which SwiftPM clones itself at
the exact revision pinned in `Package.resolved`. Every later build is offline, and nothing is downloaded when the
app runs.

**Use `scripts/build.sh` rather than `swift build`.** SwiftPM ships two build engines that keep separate object
trees, and `scripts/test.sh` pins the classic one (see [Running the tests](#running-the-tests)). A bare
`swift build` beside it compiles everything a second time into `.build/out` — measured at 826 MB next to the other
tree's 795 MB. The script pins the same engine the tests use, so there is only ever one tree.

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

It also pins `--build-system native`. SwiftPM's default engine fails here at random with `external macro implementation type 'TestingMacros.…Macro' could not be found`, always blamed on whichever test file the compiler reached first; the same sources build and pass under the classic engine, and a warm full run takes about a second instead of tens of seconds plus retries. One consequence worth knowing: the classic engine links every test target into a single bundle, so a full run prints **one** summary line for the whole suite rather than one per target. That is the complete run, not a partial one.

The default suite runs offline against sanitized fixtures. The live tests resolve two public videos and check that their streams answer. They depend on YouTube's current behaviour and are opt-in for that reason.

### What is disposable, and how to rebuild from nothing

Four directories hold nothing that cannot be recreated. None is in git, and deleting any of them costs only time —
but some of that time is a download, so it is worth knowing which:

| Directory | What it is | Deleting it costs |
|---|---|---|
| `.build/` | SwiftPM's object trees, including `repositories/` and `checkouts/` (GRDB's clone) | A full recompile, and a re-clone of GRDB over the network |
| `vendor/cache/downloads/` | The MPVKit archives `fetch-libmpv.sh` downloaded | Nothing now — it exists so a *relink* needs no network. Re-running the fetch script downloads about 330 MB again |
| `vendor/cache/libmpv/` | The linked `libmpv.2.dylib` and its headers, which the build and the app bundle both use | A re-run of `scripts/fetch-libmpv.sh`, which needs the archives above or downloads them again |
| `dist/` | The assembled `Cue.app` | A run of `scripts/make-app.sh` |

So a machine with nothing but the repository rebuilds with exactly this:

```sh
scripts/fetch-libmpv.sh   # network: about 330 MB
scripts/build.sh          # network on the first run only, for GRDB
scripts/test.sh           # proves the result
scripts/make-app.sh       # assembles and ad-hoc signs dist/Cue.app
```

Nothing else is needed, and nothing outside the repository is written except those directories. The versions that
matter are pinned rather than floating: GRDB's revision in `Package.resolved`, and libmpv's archives with their
SHA-256 checksums in `scripts/libmpv-artifacts.tsv`.

## How it works

YouTube does not offer a public API for playable streams. Cue follows the same path a YouTube client does:

1. **Parse the input.** `VideoID` accepts video ids and the common URL forms (`watch`, `youtu.be`, `shorts`, `embed`, `live`).
2. **Ask YouTube for the player response.** `WatchPage` reads a visitor token from the watch page. `InnerTube` then requests `/youtubei/v1/player` with a client profile that currently returns directly playable formats.
3. **Solve playback challenges when needed.** Some stream URLs carry obfuscated parameters (`n` and signature) that must be transformed by YouTube's own player JavaScript. `PlayerScript` locates the current player. `ChallengeSolver` runs yt-dlp's EJS solver scripts in macOS's JavaScriptCore and caches the preprocessed player.
4. **Pick the streams.** `FormatSelector` chooses the best video your Mac decodes in hardware (up to 1080p by default) and the best AAC audio, in the language YouTube marks as the video's original when it offers dubs. Only when a video offers no hardware-friendly stream does it fall back to software decoding (VP9 up to 1080p, then AV1 up to 720p), and it reports which way it went.

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
  CuePlayer/               player logic: state, commands, resume positions, window sizing,
                           subtitle and audio-track sessions
  CueQueue/                the queue itself: SQLite store and migrations, import and export,
                           thumbnails, preferences, and what each list should show
  Cue/                     the macOS app (AppKit, OpenGL video layer)
Tests/                     Swift Testing suites, sanitized fixtures and synthetic media
packaging/                 Info.plist, entitlements and license texts for the app bundle
scripts/                   test runner, libmpv fetch, app bundle and fixture scripts
```

## The queue

Cue keeps its queue in SQLite at `~/Library/Application Support/Cue/queue.sqlite`, with schema migrations, beside the
player's own data. The file is created readable only by you. Resume positions live in the same database.

The sidebar (⌃⌘S to show or hide it, ⌃⌘M to cycle its density, ⌃⌘O to float it over the video instead of pushing it
aside) lists what is left to watch with a counter of the videos still pending. It comes back as you left it: open or
closed, as wide as you dragged it, and scrolled to the same place. Each row shows its own length once that
is known. The video playing right now is marked with a tinted row and a speaker glyph; a video already watched keeps
a check mark. Titles are fetched for the rows that are on screen, so a long import does not become a long wait, and a
row shows the video's id until its title arrives. Right-clicking a row offers copying its link or opening it in your
browser.

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

## Chapters, subtitles, audio tracks and the mini player

These three live in a column at the trailing edge of the window, not in floating panels: a panel takes focus away
from the video, drifts behind the window and is easy to lose. One segmented control at its top switches pages, and
every page keeps its scroll position while the others are in front. The inspector always opens closed.

The buttons in the controls bar follow what the video actually offers: no chapters, no chapters button; no captions,
no subtitles button; a single soundtrack, no audio button. Most videos have no chapters and many have no captions,
so a bar that always showed all three mostly advertised empty pages. The keyboard and the menu still reach every
page regardless.

Chapters come from the video itself — the markers YouTube serves with the watch page, or, when there are none, the
timestamps in the description. Nothing is fetched from anywhere else, and nothing is guessed.

Subtitles are the caption tracks the video offers. Choosing one downloads it, writes it as WebVTT into a private
temporary directory and hands that file to the player, so a subtitle cannot expire in the middle of a video the way a
stream URL can. Size, colour, an optional background box and the timing offset (`z` and `x`, or the page's slider)
apply immediately, and the subtitles lift clear of the controls bar while it is on screen rather than sitting behind
it. Export writes SubRip (`.srt`) or WebVTT (`.vtt`) from the same text that is on screen.

Audio tracks are the languages a dubbed video offers. Cue plays the one YouTube marks as the video's original, rather
than whichever dub happens to be encoded at the highest bitrate, and the inspector's Audio page (`a`, or ⌃⌘A) lists the
rest. Switching is immediate: every language arrives in the same response as the video, so nothing is downloaded or
resolved again, and the picture keeps playing from exactly where it was. A video with a single soundtrack says so
instead of showing a list of one.

The mini player (⌘⇧M) moves the video into a small floating window that stays above other apps. It is the same player:
the stream is not re-resolved, playback does not pause, and closing the small window brings the video back.

Fit the window to the video (⌘0, or the button in the controls) resizes the window until the picture fills it exactly,
with no black bars on any side. Dragging a corner cannot land on that shape by hand, so once a window has been resized
there is otherwise no way back to an exact fit. It keeps the width you gave the window and moves the height, unless
that would run off the screen, and it measures the video area rather than the whole window, so an open sidebar does not
bring the bars back.

| Key | Does |
|---|---|
| `c` | Chapters page |
| `s` | Subtitles page |
| `a` | Audio languages page |
| `⌃⌘C` | Chapters page (menu) |
| `⌃⌘U` | Subtitles page (menu) |
| `⌃⌘A` | Audio languages page (menu) |
| `⌥→` / `⌥←` | Next / previous chapter |
| `z` / `x` | Subtitle delay −0.1 s / +0.1 s |
| `⌘⇧M` | Mini player |
| `⌘0` | Fit the window to the video |

## About

Cue ▸ About Cue shows the icon, the version and build, the author and Cue's own MIT license, and below them the full
text of the licenses of everything bundled — libmpv and FFmpeg under the LGPL, GRDB under MIT, the yt-dlp EJS solver
under the Unlicense, and the rest. That text is not written into the app: it is read from
`Cue.app/Contents/Resources/licenses/`, so what ships and what the window shows are the same document and cannot
drift apart.

## From the browser

Cue registers the `cue://add?url=…` scheme, so anything that can open a link can add a video: a bookmarklet, a
script, or `open` from a terminal.

**The bookmarklet** needs nothing installed. Cue ▸ Browser Integration… (also in Settings) opens a page in your
browser with a button to drag onto the bookmarks bar, and instructions for Chrome, Firefox and Safari. That page is
a plain file on disk — Cue runs no server and opens no port — and it loads nothing from the network, which is why
it can honestly say so on itself.

No browser lets an outside app create a bookmark: there is no API for it, and the alternative is writing a
browser's private bookmark store behind its back, with the browser closed, risking your own bookmarks. Cue does
not do that. One drag is as close as anything can get.

The bookmarklet is short enough to read before you install it:

```
javascript:(function(){var a=document.createElement('a');a.href='cue://add?url='+encodeURIComponent(location.href);document.body.appendChild(a);a.click();a.remove();})()
```

It clicks a synthetic link rather than assigning `location.href`, so the page you are on stays where it is, and it
is wrapped in a function that returns nothing: a `javascript:` URL that produces a value makes the browser replace
the page with that value, which is exactly what the simpler version did.

One link may carry several videos (`cue://add?url=…&url=…`), so a script handing over a list costs one trip
through the system rather than one per video. Videos Cue cannot read are skipped rather than failing the whole
link, and a link where nothing is readable says so instead of doing nothing quietly.

## Settings

⌘, opens a window with five sections. Everything in it is remembered across launches, in macOS's own preferences
store — there is no configuration file to edit and nothing is sent anywhere. A Reset button at the foot puts every
setting back to its default, and stands further from the form than the sections stand from each other, so it is not
reached for by accident.

- **Appearance.** Follow the system, or force light or dark.
- **Playback.** Whether finishing a video starts the next one.
- **Sidebar.** Its density and whether it floats over the video or pushes it aside. The choice you make with ⌃⌘M or
  ⌃⌘O is the same setting, and survives a restart.
- **Cache.** What the thumbnail cache currently weighs, a button to empty it and one to fetch the missing images.
  Emptying it costs nothing: the images come back from YouTube as rows appear.
- **Queue.** Import a file of links, add a single video, or empty the queue. Emptying asks first and cannot be undone.

## Contributing

Issues and pull requests are welcome. A few ground rules keep the project healthy:

- **Keep it native and self-contained.** No Xcode-only artefacts, no runtime downloads, no bundled interpreters.
- **Licensing.** Dependencies must be MIT-compatible or LGPL. Do not copy code from GPL projects.
- **Tests stay offline by default.** Fixtures must be sanitized: no IP addresses, session tokens or personal data. Use only the public test videos already in the suite (`dQw4w9WgXcQ`, `jNQXAC9IVRw`). For invalid ids, use obviously synthetic values such as `123456789_`.
- **Commits.** Conventional Commits, one line each.

When YouTube changes something and extraction breaks, the usual places to look are the client definitions in yt-dlp (`yt_dlp/extractor/youtube/_base.py`) and new releases of [yt-dlp/ejs](https://github.com/yt-dlp/ejs).

Both have a script, because between them they are what makes playback possible at all:

```sh
scripts/check-ejs.sh            # compare the vendored EJS scripts with the current upstream release
scripts/check-ejs.sh --update   # replace them with the upstream ones
scripts/check-client.sh         # compare Cue's InnerTube client profile with yt-dlp's definition of it
```

`check-client.sh` reports only, and never edits the profile: a difference may be a deliberate divergence, which is
a judgement call rather than something a script should decide. It is loudest in the case that matters most — a
client YouTube has retired stops resolving videos without producing a single compile error.

It also checks the checksums recorded in `third-party-licenses.md` against the files actually vendored, so the
notice cannot drift from what ships. Updating the notice itself is deliberately left to you: the script prints the
version and checksums to paste in, and the change belongs in the same commit as the new scripts. Always confirm with
`CUE_LIVE_TESTS=1 scripts/test.sh` before committing an update — the live tests resolve real videos, which is the
only thing that proves a new solver still works.

## License

Cue is released under the [MIT License](license.md).

It bundles third-party code under its own licenses, notably the yt-dlp EJS solver scripts (The Unlicense), which include meriyah (ISC) and astring (MIT), and libmpv with FFmpeg as a replaceable LGPL shared library. See [third-party-licenses.md](third-party-licenses.md).

## Disclaimer

Cue is an independent project. It is not affiliated with, endorsed by or sponsored by YouTube or Google. It is meant for personal viewing of content you are allowed to watch. You are responsible for complying with YouTube's Terms of Service and with the rights of content creators.
