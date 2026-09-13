# Third-party licenses

Cue's own code is MIT licensed (see `license.md`). Cue bundles the following third-party code.

## yt-dlp-ejs 0.8.0

Files: `Sources/CueCore/Resources/ejs/yt.solver.lib.js`, `Sources/CueCore/Resources/ejs/yt.solver.core.js`
Source: https://github.com/yt-dlp/ejs
License: The Unlicense (public domain dedication)

SHA-256 of the vendored files, for comparison with upstream releases:

- `yt.solver.lib.js`: `770831df5c46474fbff06732315b28f4fb090e427ca669a51da61e2457d41c82`
- `yt.solver.core.js`: `ca259e4e3cdd37d92fc266d9af08d4fd66da8479e240f4d984f29da402c22ead`

The lib script bundles:

- **meriyah 6.1.4** — ISC License, Copyright (c) 2019 and later, KFlash and others. https://github.com/meriyah/meriyah
- **astring 1.9.0** — MIT License, Copyright (c) 2015, David Bonnet. https://github.com/davidbonnet/astring

The full ISC and MIT license texts are reproduced in the header of `yt.solver.lib.js`.

## GRDB.swift 7.11.1

Cue stores its queue in SQLite through GRDB.swift, a SwiftPM **source** dependency pinned to an exact version
(`Package.swift`, with the resolved revision in `Package.resolved`). It is compiled into `Cue.app`, so nothing is
downloaded at first launch.

Source: https://github.com/groue/GRDB.swift
License: MIT, Copyright (C) 2015-2025 Gwendal Roué. The full text ships in
`Cue.app/Contents/Resources/licenses/grdb-mit.txt`.

GRDB links the SQLite library that ships with macOS (`libsqlite3`); no copy of SQLite is bundled. SQLite itself is in
the public domain.

## libmpv and FFmpeg (LGPL build)

`Cue.app` includes `Contents/Frameworks/libmpv.2.dylib`, a shared library that `scripts/fetch-libmpv.sh` links from the prebuilt LGPL archives of the MPVKit project, release 1.0.0 (https://github.com/mpvkit/MPVKit). Cue uses it only through libmpv's public client API. The archives and their SHA-256 checksums are pinned in `scripts/libmpv-artifacts.tsv`.

- **mpv v0.41.0-dirty**, built with `-Dgpl=false`: GNU Lesser General Public License, version 2.1 or later. https://github.com/mpv-player/mpv. The `-dirty` suffix (reported by the linked library itself) means MPVKit built it from the tagged source plus its own patches, not a clean checkout; see "Corresponding source" below for the patched sources.
- **FFmpeg n8.1.2**, built without `--enable-gpl` and with `--enable-version3`: GNU Lesser General Public License, version 3 or later. https://ffmpeg.org
- **libmpv client API headers** (`client.h`, `render.h`, `render_gl.h`; fetched at build time, not committed): ISC License.

Libraries linked into `libmpv.2.dylib`, with the licenses of their upstream projects:

| Component | License |
|---|---|
| libplacebo 7.360.1 | LGPL-2.1-or-later |
| libass 0.17.5 | ISC |
| FreeType 2.14.3 | FreeType License (FTL) |
| FriBidi 1.0.16 | LGPL-2.1-or-later |
| HarfBuzz 14.2.0 | MIT |
| libunibreak 6.1 | zlib |
| GnuTLS 3.8.11 | LGPL-2.1-or-later |
| Nettle and Hogweed | LGPL-3.0-or-later |
| GMP | LGPL-3.0-or-later |
| dav1d 1.5.3 | BSD-2-Clause |
| uavs3d 1.2.1 | BSD-3-Clause |
| libdovi 3.3.2 | MIT |
| Little CMS 2.17 | MIT |
| shaderc 2025.5.0 | Apache-2.0 |
| MoltenVK 1.4.2 | Apache-2.0 |
| libbluray 1.4.0 | LGPL-2.1-or-later |
| uchardet 0.0.8 | LGPL-2.1-or-later (chosen from MPL-1.1 / GPL-2.0-or-later / LGPL-2.1-or-later) |
| LuaJIT 2.1 | MIT |

FreeType, FriBidi, HarfBuzz and libunibreak are bundled by the `libass-build` archives (tag `0.17.5`, alongside libass itself) and are not independently versioned in `scripts/libmpv-artifacts.tsv`; their versions above were read from the vendored build, not the manifest:

- **FreeType 2.14.3** — `FREETYPE_MAJOR`/`FREETYPE_MINOR`/`FREETYPE_PATCH` in the vendored `Libfreetype.xcframework` headers (`freetype/freetype.h`).
- **FriBidi 1.0.16** — the `Shaper: FriBidi 1.0.16 (SIMPLE) …` string embedded in `libmpv.2.dylib` itself (`strings vendor/cache/libmpv/lib/libmpv.2.dylib`).
- **HarfBuzz 14.2.0** — `HB_VERSION_STRING` in the vendored `Libharfbuzz.xcframework` header (`hb-version.h`).
- **libunibreak 6.1** — `UNIBREAK_VERSION` (`0x0601`) in the vendored `Libunibreak.xcframework` header (`unibreakbase.h`); the two bytes are the major and minor version.
- **uavs3d 1.2.1** — `scripts/libmpv-artifacts.tsv`'s `libuavs3d-build` release tag, `1.2.1-fix` (the `-fix` suffix is the build repository's own decoration, not part of uavs3d's version).

The license texts ship in `Cue.app/Contents/Resources/licenses/`: `lgpl-2.1.txt`, `lgpl-3.0.txt`, `gpl-3.0.txt` (incorporated by reference in LGPL version 3) and `apache-2.0.txt`. The individual copyright notices of the permissively licensed components will be added here before the first binary release.

### Corresponding source

- The upstream releases named above.
- MPVKit's own build scripts and patches, one repository and tag per component, all pinned in `scripts/libmpv-artifacts.tsv`:
  - `Libmpv`, `Libavcodec`, `Libavdevice`, `Libavformat`, `Libavfilter`, `Libavutil`, `Libswresample`, `Libswscale`: https://github.com/mpvkit/MPVKit/tree/1.0.0
  - `gmp`, `nettle`, `hogweed`, `gnutls`: https://github.com/mpvkit/gnutls-build/tree/3.8.11
  - `Libunibreak`, `Libfreetype`, `Libfribidi`, `Libharfbuzz`, `Libass`: https://github.com/mpvkit/libass-build/tree/0.17.5
  - `Libbluray`: https://github.com/mpvkit/libbluray-build/tree/1.4.0
  - `Libuavs3d`: https://github.com/mpvkit/libuavs3d-build/tree/1.2.1-fix
  - `Libdovi`: https://github.com/mpvkit/libdovi-build/tree/3.3.2
  - `MoltenVK`: https://github.com/mpvkit/moltenvk-build/tree/1.4.2
  - `Libshaderc_combined`: https://github.com/mpvkit/libshaderc-build/tree/2025.5.0
  - `lcms2`: https://github.com/mpvkit/lcms2-build/tree/2.17.0
  - `Libplacebo`: https://github.com/mpvkit/libplacebo-build/tree/7.360.1
  - `Libdav1d`: https://github.com/mpvkit/libdav1d-build/tree/1.5.3
  - `Libuchardet`: https://github.com/mpvkit/libuchardet-build/tree/0.0.8
  - `Libluajit`: https://github.com/mpvkit/libluajit-build/tree/2.1.0-fix
- Cue's link script, `scripts/fetch-libmpv.sh`.

### Using a modified libmpv

Cue loads libmpv dynamically, so you can replace it:

1. Build a shared library that exports libmpv's client API (version 2.5), for arm64 and macOS 14 or later, with the install name `@rpath/libmpv.2.dylib`.
2. Replace `Cue.app/Contents/Frameworks/libmpv.2.dylib` with it.
3. Sign it again, the library first and then the app:

```sh
codesign --force --options runtime --timestamp=none --sign - Cue.app/Contents/Frameworks/libmpv.2.dylib
codesign --force --options runtime --timestamp=none --entitlements packaging/cue.entitlements --sign - Cue.app
```

To build Cue itself against your library, put it at `vendor/cache/libmpv/lib/libmpv.2.dylib`, put its headers in `vendor/cache/libmpv/include/mpv/`, and run `scripts/make-app.sh`.

### Rebuilding `libmpv.2.dylib`

mpv and FFmpeg are only the two outer layers: libplacebo, FriBidi, GnuTLS, Nettle, GMP, libbluray and uchardet (and the other components in the table above) are all statically linked *inside* `libmpv.2.dylib`, not shipped as separate dylibs. Producing your own build from source, rather than replacing the whole library with a compatible one you already have, means rebuilding every one of those static libraries yourself:

- MPVKit does not publish source releases of the combined dylib; it publishes one prebuilt static `xcframework.zip` per component (see `scripts/libmpv-artifacts.tsv` for the exact tags). Each component has its own build script and patch set in a separate `mpvkit/<component>-build` repository (for example `mpvkit/libplacebo-build`, `mpvkit/gnutls-build`); start from those to reproduce a component from source.
- Once you have static libraries for every component, `scripts/fetch-libmpv.sh` is the reference for how they are linked together: it force-loads `Libmpv` (so every mpv symbol survives dead-stripping), links the rest normally, restricts the dylib's exports to `mpv_*` with `-Wl,-exported_symbol,'_mpv_*'`, and dead-strips everything else. Reuse its `clang -dynamiclib` invocation (same frameworks, same `-install_name @rpath/libmpv.2.dylib`) with your own static libraries in place of the downloaded archives.

## Test media

`Tests/CuePlayerTests/Fixtures/test-video-only.mp4` and `Tests/CuePlayerTests/Fixtures/test-tone.m4a` are synthetic: FFmpeg's `testsrc2` pattern and a sine tone, generated by `scripts/make-test-media.sh`. They are part of Cue and covered by its MIT license.
