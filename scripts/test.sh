#!/bin/bash
# Runs `swift test` on Command Line Tools-only machines, where SwiftPM does not
# pass a framework search path for Testing.framework. Arguments are forwarded.
#
# The build system is pinned to `native` because SwiftPM's default `swiftbuild`
# engine fails here, constantly and at random, with "external macro
# implementation type 'TestingMacros.…Macro' could not be found", always blamed
# on whatever test file the compiler reached first. Its plugin server, not our
# code: the same sources build and pass under `native`. With `native` a warm
# full run takes about a second; under `swiftbuild` it took 20-55 seconds plus
# two or three retry cycles. Pass an explicit `--build-system` to override.
#
# The two engines report differently, and the check below knows both:
# `swiftbuild` links each test target separately and prints one "Test run with
# N tests in M suites (passed|failed)" line PER TARGET; `native` links them all
# into one bundle and prints a single aggregate line. Either way a target that
# crashes or fails to build can drop out while the process still exits 0, so an
# unfiltered run asserts the expected number of summary lines and fails loudly
# when one is missing. A filtered run (`--filter`/`--skip`) naturally reports
# fewer, so the check is skipped whenever such an argument is present.
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
chosen_system=""
previous=""
for arg in "$@"; do
  case "$arg" in
    --filter*|--skip*) filtered=1 ;;
    --build-system=*) chosen_system="${arg#--build-system=}" ;;
  esac
  if [ "$previous" = "--build-system" ]; then chosen_system="$arg"; fi
  previous="$arg"
done

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

set +e
if [ -z "$chosen_system" ]; then
  chosen_system="native"
  swift test --build-system native \
    -Xswiftc -F -Xswiftc "$frameworks" \
    -Xlinker -F -Xlinker "$frameworks" \
    -Xlinker -rpath -Xlinker "$frameworks" \
    -Xlinker -rpath -Xlinker "$libraries" \
    "$@" 2>&1 | tee "$log"
else
  swift test \
    -Xswiftc -F -Xswiftc "$frameworks" \
    -Xlinker -F -Xlinker "$frameworks" \
    -Xlinker -rpath -Xlinker "$frameworks" \
    -Xlinker -rpath -Xlinker "$libraries" \
    "$@" 2>&1 | tee "$log"
fi
status="${PIPESTATUS[0]}"
set -e

if [ "$filtered" -eq 0 ]; then
  # One aggregate line under `native`, one line per test target under `swiftbuild`.
  if [ "$chosen_system" = "native" ]; then
    expected=1
  else
    # `grep -c` exits 1 when it matches nothing, which under `set -e` would abort this script before the
    # message below is printed - and no summary lines at all is exactly the failure worth explaining.
    expected="$(grep -c '^[[:space:]]*\.testTarget(' "$repo/Package.swift" || true)"
  fi
  reported="$(grep -cE '^(✔|✘) Test run with [0-9]+ tests? in [0-9]+ suites? (passed|failed)' "$log" || true)"
  if [ "$reported" -ne "$expected" ]; then
    echo "scripts/test.sh: expected $expected test summary line(s) under --build-system $chosen_system, got $reported." >&2
    echo "scripts/test.sh: a target's run did not report - check for a build failure or a crash above." >&2
    status=1
  fi
fi

exit "$status"
