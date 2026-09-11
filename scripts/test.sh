#!/bin/sh
# Runs `swift test` on Command Line Tools-only machines, where SwiftPM does not
# pass a framework search path for Testing.framework. Arguments are forwarded.
set -eu

developer_dir="$(xcode-select -p)"
frameworks="$developer_dir/Library/Developer/Frameworks"
libraries="$developer_dir/Library/Developer/usr/lib"

exec swift test \
  -Xswiftc -F -Xswiftc "$frameworks" \
  -Xlinker -F -Xlinker "$frameworks" \
  -Xlinker -rpath -Xlinker "$frameworks" \
  -Xlinker -rpath -Xlinker "$libraries" \
  "$@"
