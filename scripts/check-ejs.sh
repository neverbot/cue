#!/bin/bash
# Compares the vendored yt-dlp EJS solver scripts against the current upstream release.
#
# Why this matters more than a version bump usually does: these scripts are what solve YouTube's signature and
# `n` challenges. When YouTube changes them, playback stops working for everyone until yt-dlp ships a fix and we
# vendor it. Nothing in the app can work around that, so knowing whether the vendored copies are behind is the
# first question to ask when extraction breaks — and worth asking occasionally when it has not.
#
#   scripts/check-ejs.sh            # report only
#   scripts/check-ejs.sh --update   # also replace the vendored files with the upstream ones
#
# --update rewrites the two scripts and prints the new checksums. It deliberately does NOT edit
# third-party-licenses.md: the version and the checksums recorded there must be updated by hand, in the same
# commit, so the licence notice cannot silently drift from what is actually shipped. The script prints exactly
# what to put there.
#
# Exit codes: 0 up to date, 3 an update is available (or was applied), 1 something went wrong.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
vendored="$repo/Sources/CueCore/Resources/ejs"
notices="$repo/third-party-licenses.md"
release_api=https://api.github.com/repos/yt-dlp/ejs/releases/latest
files=(yt.solver.core.js yt.solver.lib.js)

update=0
if [ "${1:-}" = "--update" ]; then
    update=1
elif [ "$#" -gt 0 ]; then
    echo "usage: $0 [--update]" >&2
    exit 1
fi

for name in "${files[@]}"; do
    test -f "$vendored/$name" || { echo "missing vendored file: $vendored/$name" >&2; exit 1; }
done

# The recorded version and checksums, so a mismatch between the repository's own notice and its own files is
# caught too. That drift is silent otherwise, and the notice is the part a reader trusts.
recorded_version=$(sed -n 's/^## yt-dlp-ejs \(.*\)$/\1/p' "$notices" | head -1)
echo "vendored version (per third-party-licenses.md): ${recorded_version:-unknown}"

for name in "${files[@]}"; do
    actual=$(shasum -a 256 "$vendored/$name" | cut -d' ' -f1)
    recorded=$(sed -n "s/^- \`$name\`: \`\([0-9a-f]\{64\}\)\`.*/\1/p" "$notices" | head -1)
    if [ -n "$recorded" ] && [ "$actual" != "$recorded" ]; then
        echo "MISMATCH inside the repository: $name is $actual but the licence notice records $recorded" >&2
        exit 1
    fi
done
echo "the licence notice matches the vendored files"

release=$(curl -sS --max-time 30 "$release_api")
tag=$(printf '%s' "$release" | jq -r '.tag_name // empty')
test -n "$tag" || { echo "could not read the latest release from $release_api" >&2; exit 1; }
echo "latest upstream release: $tag"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

behind=0
for name in "${files[@]}"; do
    url=$(printf '%s' "$release" | jq -r --arg n "$name" '.assets[] | select(.name == $n) | .browser_download_url')
    test -n "$url" || { echo "release $tag has no asset named $name" >&2; exit 1; }
    curl -sSL --max-time 120 -o "$work/$name" "$url"
    upstream=$(shasum -a 256 "$work/$name" | cut -d' ' -f1)
    current=$(shasum -a 256 "$vendored/$name" | cut -d' ' -f1)
    if [ "$upstream" = "$current" ]; then
        echo "  $name: identical"
    else
        behind=1
        echo "  $name: DIFFERS — upstream $upstream, vendored $current"
    fi
done

if [ "$behind" -eq 0 ]; then
    echo "up to date with $tag"
    exit 0
fi

if [ "$update" -eq 0 ]; then
    echo
    echo "An update is available. Re-run with --update, then edit $notices by hand and run the live tests:"
    echo "  CUE_LIVE_TESTS=1 scripts/test.sh"
    exit 3
fi

for name in "${files[@]}"; do
    cp "$work/$name" "$vendored/$name"
done

echo
echo "Updated. Put this in third-party-licenses.md, replacing the yt-dlp-ejs section's version and checksums:"
echo "## yt-dlp-ejs ${tag#v}"
for name in "${files[@]}"; do
    echo "- \`$name\`: \`$(shasum -a 256 "$vendored/$name" | cut -d' ' -f1)\`"
done
echo
echo "Then confirm extraction still works before committing:"
echo "  CUE_LIVE_TESTS=1 scripts/test.sh"
exit 3
