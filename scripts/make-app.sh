#!/bin/bash
# Builds dist/Cue.app with Command Line Tools only: release build, bundle layout, libmpv in Frameworks, solver
# scripts, license notices and icon; ad-hoc signature with the hardened runtime; verification.
# usage: scripts/make-app.sh [--output <directory>]
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
out="$repo/dist"
while [ $# -gt 0 ]; do
  case "$1" in
    --output) mkdir -p "$2"; out=$(cd "$2" && pwd); shift ;;
    *) echo "usage: scripts/make-app.sh [--output <directory>]" >&2; exit 2 ;;
  esac
  shift
done
app="$out/Cue.app"
dylib="$repo/vendor/cache/libmpv/lib/libmpv.2.dylib"
[ -f "$dylib" ] || { echo "libmpv is missing: run scripts/fetch-libmpv.sh first" >&2; exit 1; }

# 1. Release build. The prefix maps keep absolute source paths out of the binary; mapping only Sources (not the
#    repository root) avoids breaking Clang's module cache, which lives under .build.
#    The engine is pinned for two reasons. One: SwiftPM's default engine keeps its own object tree at
#    `.build/out`, so bundling with it while `scripts/test.sh` and `scripts/build.sh` use the classic one means
#    compiling everything twice, into two trees of roughly 800 MB each. Two, and worse: the `--show-bin-path`
#    below must come from the same engine that just compiled, or this script copies a binary out of the other
#    tree — stale, or missing entirely.
flags=(-c release --build-system native
  -Xswiftc -file-prefix-map -Xswiftc "$repo/Sources=Sources"
  -Xcc -ffile-prefix-map="$repo/Sources=Sources")
swift build "${flags[@]}" --product Cue
bin_dir=$(swift build "${flags[@]}" --show-bin-path)

# 2. Icon, regenerated only when its script changes.
icon_dir="$repo/.build/cue-icon"
if [ ! -f "$icon_dir/AppIcon.icns" ] || [ "$repo/scripts/make-icon.swift" -nt "$icon_dir/AppIcon.icns" ]; then
  rm -rf "$icon_dir"
  mkdir -p "$icon_dir"
  swift "$repo/scripts/make-icon.swift" "$icon_dir/AppIcon.iconset"
  iconutil -c icns -o "$icon_dir/AppIcon.icns" "$icon_dir/AppIcon.iconset"
fi

# 3. Bundle layout.
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks" "$app/Contents/Resources/licenses"
cp "$repo/packaging/Info.plist" "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist" >/dev/null
exe="$app/Contents/MacOS/Cue"
cp "$bin_dir/Cue" "$exe"
cp "$dylib" "$app/Contents/Frameworks/libmpv.2.dylib"
# ChallengeSolver.bundled() looks in Contents/Resources/ejs first.
cp -R "$repo/Sources/CueCore/Resources/ejs" "$app/Contents/Resources/ejs"
cp "$icon_dir/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
cp "$repo/license.md" "$repo/third-party-licenses.md" "$repo"/packaging/licenses/*.txt "$app/Contents/Resources/licenses/"

# 4. Replace SwiftPM's build-machine rpaths (they point into vendor/cache) with the bundle-relative one.
otool -l "$exe" | awk '/cmd LC_RPATH/ { getline; getline; print $2 }' | while IFS= read -r rpath; do
  [ -n "$rpath" ] || continue
  install_name_tool -delete_rpath "$rpath" "$exe"
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$exe"

# 5. Every non-system dependency must resolve inside the bundle.
for binary in "$exe" "$app/Contents/Frameworks/libmpv.2.dylib"; do
  # `|| true`: grep exits 1 when every dependency is a system one, which pipefail + set -e would turn into an abort.
  for dependency in $({ otool -L "$binary" | tail -n +2 | awk '{print $1}' | grep -v -E '^(/System/Library/|/usr/lib/)' || true; }); do
    case "$dependency" in
      @rpath/*) [ -e "$app/Contents/Frameworks/${dependency#@rpath/}" ] || { echo "unresolved $dependency in $binary" >&2; exit 1; } ;;
      *) echo "non-relocatable dependency $dependency in $binary" >&2; exit 1 ;;
    esac
  done
done

# 6. No absolute paths from this machine in the executable.
leaks=$(strings -a "$exe" | grep -c "$HOME" || true)
[ "$leaks" = 0 ] || { echo "the executable contains $leaks strings with the home directory path" >&2; exit 1; }

# 7. Sign inside-out (no --deep): the dylib, then the bundle with its entitlements. Ad-hoc signatures carry no Team ID,
#    so the entitlements disable library validation until Developer ID signing replaces them.
codesign --force --options runtime --timestamp=none --sign - "$app/Contents/Frameworks/libmpv.2.dylib"
codesign --force --options runtime --timestamp=none --entitlements "$repo/packaging/cue.entitlements" --sign - "$app"

# 8. Verify.
codesign --verify --strict --verbose=2 "$app"
codesign -d --entitlements - "$app" 2>/dev/null | grep -q "com.apple.security.cs.allow-jit" \
  || { echo "allow-jit entitlement missing" >&2; exit 1; }
codesign -dvv "$app" 2>&1 | grep -E '^(Identifier|Format|CodeDirectory|Signature)='
du -sh "$app"
