#!/bin/bash
# Compares Cue's InnerTube client profile against yt-dlp's definition of the same client.
#
# The other half of what keeps extraction alive. `scripts/check-ejs.sh` watches the solver scripts; this watches
# the client Cue pretends to be when it asks YouTube for a video. YouTube retires clients without warning — the
# `tv` client died in 2026 — and when that happens the symptom is not a compile error but videos that stop
# resolving. yt-dlp tracks these definitions closely, so a difference here is an early warning worth having.
#
#   scripts/check-client.sh
#
# Reports only; it never edits the profile. A field that differs may be a deliberate divergence, so what to do
# about it is a judgement call, not something a script should make on its own.
#
# Exit codes: 0 identical, 3 a difference (or the client is gone upstream), 1 something went wrong.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
profile="$repo/Sources/CueCore/YouTube/ClientProfile.swift"
upstream=https://raw.githubusercontent.com/yt-dlp/yt-dlp/master/yt_dlp/extractor/youtube/_base.py
client=visionos

test -f "$profile" || { echo "missing $profile" >&2; exit 1; }

base=$(curl -sSL --max-time 30 "$upstream")
test -n "$base" || { echo "could not fetch $upstream" >&2; exit 1; }

# The client's own block, from its key to the closing brace at the same indentation.
block=$(printf '%s\n' "$base" | awk "/^    '$client': \{/,/^    \},/")
if [ -z "$block" ]; then
    echo "yt-dlp no longer defines the '$client' client." >&2
    echo "That is the loud case: a retired client stops resolving videos with no compile error." >&2
    echo "Pick the client yt-dlp uses now and port its definition into $profile." >&2
    exit 3
fi

differences=0

check() {
    local label=$1 value=$2
    if [ -z "$value" ]; then
        echo "  $label: not found upstream — the shape of _base.py may have changed"
        differences=1
    elif grep -qF -- "$value" "$profile"; then
        echo "  $label: matches"
    else
        echo "  $label: DIFFERS — upstream has $value"
        differences=1
    fi
}

echo "comparing $profile with yt-dlp's '$client' client"

for key in clientName clientVersion deviceMake deviceModel userAgent osName osVersion; do
    check "$key" "$(printf '%s\n' "$block" | sed -n "s/^ *'$key': '\(.*\)',$/\1/p" | head -1)"
done

check "clientNameID" "$(printf '%s\n' "$block" | sed -n "s/^ *'INNERTUBE_CONTEXT_CLIENT_NAME': \([0-9]*\),$/\1/p" | head -1)"

# REQUIRE_JS_PLAYER decides whether the signature and `n` challenges have to be solved at all, so a change here
# is a behaviour change, not a cosmetic one.
# -E, because this is the one pattern here that needs alternation and BSD sed does not take `\|` in a basic
# expression: it silently matches nothing, which reads as "the field vanished upstream" rather than as a bug.
requires=$(printf '%s\n' "$block" | sed -n -E "s/^ *'REQUIRE_JS_PLAYER': (True|False),$/\1/p" | head -1)
case "$requires" in
    True) check "requiresPlayerJS" "requiresPlayerJS: true" ;;
    False) check "requiresPlayerJS" "requiresPlayerJS: false" ;;
    *) echo "  requiresPlayerJS: not found upstream"; differences=1 ;;
esac

if [ "$differences" -eq 0 ]; then
    echo "identical to yt-dlp"
    exit 0
fi

echo
echo "A difference is not automatically a bug, but it is worth understanding before extraction breaks."
echo "After changing the profile, prove it against real videos:"
echo "  CUE_LIVE_TESTS=1 scripts/test.sh"
exit 3
