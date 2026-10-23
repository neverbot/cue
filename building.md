# Building Cue from source

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
tree's 795 MB. The script pins the same engine the tests use, so there is only ever one tree. For the same reason,
`swift run` is written `swift run --build-system native` everywhere in this repository.

## Building and running the app

```sh
scripts/make-app.sh                                                     # builds and signs dist/Cue.app (ad-hoc)
open dist/Cue.app --args "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

You can also start Cue without arguments and paste a YouTube link with ⌘V. The keyboard shortcuts are in the
[readme](readme.md#keyboard).

An app you build yourself is never quarantined: quarantine is attached by whatever downloads a file, so a bundle
produced by `scripts/make-app.sh` on your own machine launches straight away.

## Running the tests

```sh
scripts/test.sh                            # offline test suite
scripts/test.sh --filter ExtractorTests    # a subset
CUE_LIVE_TESTS=1 scripts/test.sh           # also run tests that contact YouTube
CUE_MPV_TESTS=1 scripts/test.sh            # also play a synthetic clip through libmpv
```

Use `scripts/test.sh` rather than `swift test`. On a machine with only the Command Line Tools installed, SwiftPM does not find the Swift Testing framework on its own. The script adds the missing framework search paths and forwards any arguments to `swift test`.

It also pins `--build-system native`. SwiftPM's default engine fails here at random with `external macro implementation type 'TestingMacros.…Macro' could not be found`, always blamed on whichever test file the compiler reached first; the same sources build and pass under the classic engine, and a warm full run takes about a second instead of tens of seconds plus retries. One consequence worth knowing: the classic engine links every test target into a single bundle, so a full run prints **one** summary line for the whole suite rather than one per target. That is the complete run, not a partial one.

The default suite runs offline against sanitized fixtures. The live tests resolve two public videos and check that their streams answer. They depend on YouTube's current behaviour and are opt-in for that reason.

## What is disposable, and how to rebuild from nothing

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

## Project layout

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
