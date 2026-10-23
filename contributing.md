# Contributing to Cue

Issues and pull requests are welcome. [building.md](building.md) covers how to build, test and package the app,
and the project layout. A few ground rules keep the project healthy:

- **Keep it native and self-contained.** No Xcode-only artefacts, no runtime downloads, no bundled interpreters.
- **Licensing.** Dependencies must be MIT-compatible or LGPL. Do not copy code from GPL projects.
- **Tests stay offline by default.** Fixtures must be sanitized: no IP addresses, session tokens or personal data. Use only the public test videos already in the suite (`dQw4w9WgXcQ`, `jNQXAC9IVRw`). For invalid ids, use obviously synthetic values such as `123456789_`.
- **Commits.** Conventional Commits, one line each.

## When extraction breaks

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

`check-ejs.sh`, for its part, also checks the checksums recorded in `third-party-licenses.md` against the files
actually vendored, so the notice cannot drift from what ships. Updating the notice itself is deliberately left to you: the script prints the
version and checksums to paste in, and the change belongs in the same commit as the new scripts. Always confirm with
`CUE_LIVE_TESTS=1 scripts/test.sh` before committing an update — the live tests resolve real videos, which is the
only thing that proves a new solver still works.
