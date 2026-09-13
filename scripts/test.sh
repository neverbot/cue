#!/bin/bash
# Runs `swift test` on Command Line Tools-only machines, where SwiftPM does not
# pass a framework search path for Testing.framework. Arguments are forwarded.
#
# Swift Testing prints one "Test run with N tests in M suites (passed|failed)"
# line per test target, not one line for the whole run. A target that crashes
# or fails to build can drop out silently while the other targets still run
# and the process still exits 0 - the last line on screen then looks like the
# whole suite when it only covers a fraction of it. On a plain, unfiltered
# run this script counts those per-target lines against the test targets
# declared in Package.swift and fails loudly if any are missing. A filtered
# run (`--filter`/`--skip`, or a target named directly) naturally covers fewer
# targets, so the check is skipped whenever such an argument is present.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
if [ ! -f "$repo/vendor/cache/libmpv/lib/libmpv.2.dylib" ]; then
  echo "libmpv is missing: run scripts/fetch-libmpv.sh first" >&2
  exit 1
fi

developer_dir="$(xcode-select -p)"
frameworks="$developer_dir/Library/Developer/Frameworks"
libraries="$developer_dir/Library/Developer/usr/lib"

filtered=0
for arg in "$@"; do
  case "$arg" in
    --filter*|--skip*) filtered=1 ;;
  esac
done

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

set +e
swift test \
  -Xswiftc -F -Xswiftc "$frameworks" \
  -Xlinker -F -Xlinker "$frameworks" \
  -Xlinker -rpath -Xlinker "$frameworks" \
  -Xlinker -rpath -Xlinker "$libraries" \
  "$@" 2>&1 | tee "$log"
status="${PIPESTATUS[0]}"
set -e

if [ "$filtered" -eq 0 ]; then
  # `grep -c` exits 1 when it matches nothing, which under `set -e` would abort this script before the
  # message below is printed - and no summary lines at all is exactly the failure worth explaining.
  expected="$(grep -c '^[[:space:]]*\.testTarget(' "$repo/Package.swift" || true)"
  reported="$(grep -cE '^(✔|✘) Test run with [0-9]+ tests? in [0-9]+ suites? (passed|failed)' "$log" || true)"
  if [ "$reported" -ne "$expected" ]; then
    echo "scripts/test.sh: expected $expected test target summaries (from Package.swift), got $reported." >&2
    echo "scripts/test.sh: a target's run did not report - check for a build failure or a crash above." >&2
    status=1
  fi
fi

exit "$status"
