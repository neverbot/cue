#!/bin/sh
# Regenerates the synthetic media fixtures used by the libmpv integration tests:
#   Tests/CuePlayerTests/Fixtures/test-video-only.mp4  3 s, 320x180, 25 fps H.264 test pattern, no audio
#   Tests/CuePlayerTests/Fixtures/test-tone.m4a        3 s, 880 Hz mono AAC tone
# The committed files are what the tests use; this script only documents how they were made. It needs ffmpeg with
# libx264, which is not part of Cue's build and is not required to build or test Cue.
set -eu

repo=$(cd "$(dirname "$0")/.." && pwd)
fixtures="$repo/Tests/CuePlayerTests/Fixtures"
command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg is not installed; the committed fixtures are still usable" >&2; exit 1; }
mkdir -p "$fixtures"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=320x180:rate=25:duration=3" -an \
  -c:v libx264 -profile:v baseline -pix_fmt yuv420p -g 25 -crf 32 -threads 1 \
  -map_metadata -1 -fflags +bitexact -flags:v +bitexact -movflags +faststart \
  "$fixtures/test-video-only.mp4"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "sine=frequency=880:sample_rate=44100:duration=3" \
  -c:a aac -b:a 48k -ac 1 \
  -map_metadata -1 -fflags +bitexact -flags:a +bitexact -movflags +faststart \
  "$fixtures/test-tone.m4a"

shasum -a 256 "$fixtures/test-video-only.mp4" "$fixtures/test-tone.m4a"
