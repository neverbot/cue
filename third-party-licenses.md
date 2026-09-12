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

## libmpv and FFmpeg (LGPL build)

`Cue.app` includes `Contents/Frameworks/libmpv.2.dylib`, a shared library that `scripts/fetch-libmpv.sh` links from the prebuilt LGPL archives of the MPVKit project, release 1.0.0 (https://github.com/mpvkit/MPVKit). Cue uses it only through libmpv's public client API. The archives and their SHA-256 checksums are pinned in `scripts/libmpv-artifacts.tsv`.

- **mpv v0.41.0**, built with `-Dgpl=false`: GNU Lesser General Public License, version 2.1 or later. https://github.com/mpv-player/mpv
- **FFmpeg n8.1.2**, built without `--enable-gpl` and with `--enable-version3`: GNU Lesser General Public License, version 3 or later. https://ffmpeg.org
- **libmpv client API headers** (`client.h`, `render.h`, `render_gl.h`; fetched at build time, not committed): ISC License.

Libraries linked into `libmpv.2.dylib`, with the licenses of their upstream projects:

| Component | License |
|---|---|
| libplacebo 7.360.1 | LGPL-2.1-or-later |
| libass 0.17.5 | ISC |
| FreeType | FreeType License (FTL) |
| FriBidi | LGPL-2.1-or-later |
| HarfBuzz | MIT |
| libunibreak | zlib |
| GnuTLS 3.8.11 | LGPL-2.1-or-later |
| Nettle and Hogweed | LGPL-3.0-or-later |
| GMP | LGPL-3.0-or-later |
| dav1d 1.5.3 | BSD-2-Clause |
| uavs3d | BSD-3-Clause |
| libdovi 3.3.2 | MIT |
| Little CMS 2.17 | MIT |
| shaderc 2025.5.0 | Apache-2.0 |
| MoltenVK 1.4.2 | Apache-2.0 |
| libbluray 1.4.0 | LGPL-2.1-or-later |
| uchardet 0.0.8 | LGPL-2.1-or-later (chosen from MPL-1.1 / GPL-2.0-or-later / LGPL-2.1-or-later) |
| LuaJIT 2.1 | MIT |

The license texts ship in `Cue.app/Contents/Resources/licenses/`: `lgpl-2.1.txt`, `lgpl-3.0.txt`, `gpl-3.0.txt` (incorporated by reference in LGPL version 3) and `apache-2.0.txt`. The individual copyright notices of the permissively licensed components will be added here before the first binary release.

### Corresponding source

- The upstream releases listed above.
- MPVKit's build scripts and patches at tag 1.0.0: https://github.com/mpvkit/MPVKit/tree/1.0.0
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
