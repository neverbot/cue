#!/bin/bash
# Builds Cue with the build engine pinned, and forwards any arguments to `swift build`.
#
# Why this exists, when `swift build` would do: SwiftPM ships two build engines, and they keep *separate* object
# trees. The default one fills `.build/out`; the classic one fills `.build/<triple>`. `scripts/test.sh` pins the
# classic engine because the default fails here at random with the `TestingMacros` error — so a bare `swift build`
# beside it means the same code compiled twice, into two trees, roughly 800 MB each. That is not a hypothetical:
# it was measured at 826 MB and 795 MB side by side on a disk at 94%.
#
#   scripts/build.sh                       # build everything
#   scripts/build.sh --product Cue         # or any other `swift build` arguments
#
# **This flag is living on borrowed time.** SwiftPM prints "'--build-system native' has been deprecated and will
# be removed in a future release". When it goes, both this script and `scripts/test.sh` need revisiting together:
# the pin exists for the macro flake, not for tidiness, so the flake has to be re-tested against whatever the
# default engine has become before the pin can simply be dropped.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)

if [ ! -f "$repo/vendor/cache/libmpv/lib/libmpv.2.dylib" ]; then
    echo "libmpv is missing. Run scripts/fetch-libmpv.sh first (it downloads and links it)." >&2
    exit 1
fi

exec swift build --build-system native "$@"
