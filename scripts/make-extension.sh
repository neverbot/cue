#!/bin/bash
# Assembles the browser extension into one directory and one zip per browser.
#
# The two browsers need different manifests — Chrome runs the background as a service worker, Firefox as an event
# page listing its scripts, and Firefox needs an add-on id — but every other file is shared. Rather than keep two
# copies of the code, the sources live once in extension/ and this script pairs them with the right manifest.
#
#   scripts/make-extension.sh
#
# Output goes in dist/extension/, which is git-ignored like the rest of dist/.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
source_dir="$repo/extension"
out="$repo/dist/extension"
shared=(cue.js background.js options.html options.js)

rm -rf "$out"
mkdir -p "$out"

for browser in chrome firefox; do
    manifest="$source_dir/manifest.$browser.json"
    test -f "$manifest" || { echo "missing $manifest" >&2; exit 1; }
    # The manifest must be valid JSON before it is shipped: a browser rejects the whole extension for a stray
    # comma, and it does so at install time, which is the worst moment to find out.
    if command -v jq >/dev/null 2>&1; then
        jq empty "$manifest" || { echo "$manifest is not valid JSON" >&2; exit 1; }
    fi

    target="$out/$browser"
    mkdir -p "$target"
    cp "$manifest" "$target/manifest.json"
    for file in "${shared[@]}"; do
        cp "$source_dir/$file" "$target/$file"
    done

    # `cd` into the directory so paths inside the zip are relative to the extension root, which is what both
    # browsers expect; a zip containing `chrome/manifest.json` installs as nothing at all.
    (cd "$target" && zip -q -r "../$browser.zip" .)
    echo "$browser: $target (and $out/$browser.zip)"
done

echo
echo "Chrome:  chrome://extensions → Developer mode → Load unpacked → $out/chrome"
echo "Firefox: about:debugging#/runtime/this-firefox → Load Temporary Add-on → $out/firefox/manifest.json"
