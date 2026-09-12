#!/bin/bash
# Downloads MPVKit's prebuilt LGPL libmpv and FFmpeg archives (never the GPL variants), verifies their SHA-256
# checksums and links them into one shared library:
#   vendor/cache/libmpv/lib/libmpv.2.dylib   install name @rpath/libmpv.2.dylib, arm64, exports only mpv_*
#   vendor/cache/libmpv/include/mpv/*.h      libmpv client API headers (ISC license)
# Linking dynamically keeps libmpv replaceable, as the LGPL requires. See third-party-licenses.md for relinking.
# usage: scripts/fetch-libmpv.sh [--force]
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
manifest="$repo/scripts/libmpv-artifacts.tsv"
cache="$repo/vendor/cache"
downloads="$cache/downloads"
extracted="$cache/extracted"
out="$cache/libmpv"
dylib="$out/lib/libmpv.2.dylib"
stamp="$out/stamp"

force=0
case "${1:-}" in
  "") ;;
  --force) force=1 ;;
  *) echo "usage: scripts/fetch-libmpv.sh [--force]" >&2; exit 2 ;;
esac

[ "$(uname -m)" = arm64 ] || { echo "Cue builds for Apple silicon (arm64) only" >&2; exit 1; }

fingerprint=$(cat "$manifest" "$0" | shasum -a 256 | awk '{print $1}')
if [ "$force" = 0 ] && [ -f "$dylib" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$fingerprint" ]; then
  echo "libmpv is up to date: $dylib"
  exit 0
fi

mkdir -p "$downloads" "$extracted" "$out/lib" "$out/include/mpv"

archives=()
libmpv_archive=""
while IFS=$'\t' read -r name sha256 url; do
  case "$name" in ''|'#'*) continue ;; esac
  shopt -s nocasematch
  case "$name$url" in *GPL*|*smbclient*) echo "refusing non-LGPL artifact $name" >&2; exit 1 ;; esac
  shopt -u nocasematch

  zip="$downloads/$name.xcframework.zip"
  if [ ! -f "$zip" ] || [ "$(shasum -a 256 "$zip" | awk '{print $1}')" != "$sha256" ]; then
    echo "downloading $name"
    curl -fsSL --retry 3 -o "$zip.partial" "$url"
    mv "$zip.partial" "$zip"
  fi
  actual=$(shasum -a 256 "$zip" | awk '{print $1}')
  if [ "$actual" != "$sha256" ]; then
    echo "checksum mismatch for $name: expected $sha256, got $actual" >&2
    rm -f "$zip"
    exit 1
  fi

  rm -rf "${extracted:?}/$name"
  mkdir -p "$extracted/$name"
  unzip -q "$zip" -d "$extracted/$name"
  slice=$(find "$extracted/$name" -type d -path '*.xcframework/macos-*' -prune | head -n 1)
  [ -n "$slice" ] || { echo "no macOS slice in $name" >&2; exit 1; }
  binary=$(find "$slice" -type f \( -name "$name" -o -name "lib$name.a" \) | head -n 1)
  [ -n "$binary" ] || { echo "no static library in the macOS slice of $name" >&2; exit 1; }

  if [ "$name" = Libmpv ]; then
    libmpv_archive=$binary
    headers=$(find "$slice" -type d -path '*/Headers/mpv' | head -n 1)
    cp "$headers/client.h" "$headers/render.h" "$headers/render_gl.h" "$out/include/mpv/"
  else
    archives+=("$binary")
  fi
done < "$manifest"
[ -n "$libmpv_archive" ] || { echo "Libmpv missing from $manifest" >&2; exit 1; }

sdk=$(xcrun --show-sdk-path)
toolchain_swift="$(xcode-select -p)/usr/lib/swift/macosx"
frameworks=(
  AVFoundation AppKit AudioToolbox Carbon Cocoa CoreAudio CoreFoundation CoreGraphics CoreMedia CoreServices CoreText
  CoreVideo DiskArbitration Foundation GameController IOKit IOSurface MediaPlayer Metal OpenGL QuartzCore
  QuickLookThumbnailing Security VideoToolbox
)
framework_flags=()
for framework in "${frameworks[@]}"; do framework_flags+=(-framework "$framework"); done

echo "linking $dylib"
clang -dynamiclib -arch arm64 -mmacosx-version-min=14.0 \
  -o "$dylib.partial" -install_name @rpath/libmpv.2.dylib \
  -Wl,-force_load,"$libmpv_archive" "${archives[@]}" \
  -L"$sdk/usr/lib/swift" -L"$toolchain_swift" \
  "${framework_flags[@]}" \
  -lbz2 -liconv -lexpat -lresolv -lxml2 -lz -lc++ \
  -Wl,-exported_symbol,'_mpv_*' -Wl,-dead_strip
strip -x "$dylib.partial"
mv "$dylib.partial" "$dylib"

exported=$(nm -gU "$dylib" | grep -c ' _mpv_' || true)
[ "$exported" -ge 50 ] || { echo "expected at least 50 exported mpv_* symbols, found $exported" >&2; exit 1; }
# `|| true`: grep exits 1 when every dependency is a system library, which is the success case.
foreign=$({ otool -L "$dylib" | tail -n +2 | awk '{print $1}' | grep -v -E '^(/System/Library/|/usr/lib/|@rpath/libmpv\.2\.dylib$)' || true; })
[ -z "$foreign" ] || { echo "libmpv depends on non-system libraries: $foreign" >&2; exit 1; }

# Smoke test: initialize a headless core and confirm the LGPL configuration.
probe_dir=$(mktemp -d)
trap 'rm -rf "$probe_dir"' EXIT
cat > "$probe_dir/probe.c" <<'C'
#include <stdio.h>
#include <string.h>
#include <mpv/client.h>
int main(void) {
    mpv_handle *handle = mpv_create();
    if (!handle) return 1;
    mpv_set_option_string(handle, "vo", "null");
    mpv_set_option_string(handle, "ao", "null");
    mpv_set_option_string(handle, "config", "no");
    if (mpv_initialize(handle) < 0) return 1;
    char *configuration = mpv_get_property_string(handle, "mpv-configuration");
    int lgpl = configuration && strstr(configuration, "-Dgpl=false") != NULL;
    char *version = mpv_get_property_string(handle, "mpv-version");
    printf("%s, LGPL build: %s\n", version ? version : "unknown mpv", lgpl ? "yes" : "no");
    mpv_free(version);
    mpv_free(configuration);
    mpv_terminate_destroy(handle);
    return lgpl ? 0 : 1;
}
C
clang -arch arm64 -mmacosx-version-min=14.0 -I"$out/include" -L"$out/lib" -lmpv.2 -Wl,-rpath,"$out/lib" \
  -o "$probe_dir/probe" "$probe_dir/probe.c"
"$probe_dir/probe"

echo "$fingerprint" > "$stamp"
du -h "$dylib"
