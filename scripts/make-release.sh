#!/bin/bash
# Builds a release of Cue and files it on GitHub as a draft.
#
# usage: scripts/make-release.sh <version> [--dry-run] [--yes]
#
# The release is always created as a draft, and a draft carries no tag: GitHub creates `v<version>` only when you
# press Publish. Until then nothing about this release is visible to anyone, and the one thing that does leave this
# machine — the commit that records the new version — is pushed only after you confirm it.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo"

version=""
dry_run=no
assume_yes=no
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=yes ;;
    --yes) assume_yes=yes ;;
    -*) echo "usage: scripts/make-release.sh <version> [--dry-run] [--yes]" >&2; exit 2 ;;
    *) [ -z "$version" ] || { echo "only one version, please" >&2; exit 2; }; version="$1" ;;
  esac
  shift
done
[ -n "$version" ] || { echo "usage: scripts/make-release.sh <version> [--dry-run] [--yes]" >&2; exit 2; }

say() { printf '\n==> %s\n' "$1"; }
die() { echo "$1" >&2; exit 1; }

# 1. Refuse early, and for one reason at a time. Everything below this point either succeeds or leaves the
#    repository as it found it, so the expensive half never starts on a tree that cannot produce a release.
say "Checking the ground"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "the version must look like 1.2.3, not '$version'"
IFS=. read -r major minor patch <<<"$version"
# CFBundleVersion is a single integer macOS requires to grow from one release to the next. Deriving it from the
# three parts keeps that promise without anything to remember, as long as two of them stay below a hundred.
[ "$minor" -lt 100 ] && [ "$patch" -lt 100 ] || die "minor and patch must each be below 100 to derive CFBundleVersion"
bundle_version=$((major * 10000 + minor * 100 + patch))

[ -z "$(git status --porcelain)" ] || die "the working tree has changes; commit or stash them first"
branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" = master ] || die "releases are cut from master, not from '$branch'"

git fetch --quiet origin master
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/master)" ] \
  || die "master and origin/master differ; push or pull first so the only new commit is the version bump"

git fetch --quiet --tags origin
git rev-parse -q --verify "refs/tags/v$version" >/dev/null && die "tag v$version already exists"
gh release view "v$version" >/dev/null 2>&1 && die "a release v$version already exists on GitHub"

command -v gh >/dev/null || die "the gh command line tool is not installed"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated; run: gh auth login"
[ -f "$repo/vendor/cache/libmpv/lib/libmpv.2.dylib" ] || die "libmpv is missing: run scripts/fetch-libmpv.sh first"

current=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$repo/packaging/Info.plist")
echo "version      $current -> $version"
echo "bundle       $bundle_version"
echo "commit       $(git rev-parse --short HEAD)"

# 2. A release of code whose tests fail is a bug with a version number on it.
say "Running the tests"
"$repo/scripts/test.sh"

# 3. Record the version. Its own commit, so the diff of a release is one line of plist and nothing else.
say "Recording the version"
plutil -replace CFBundleShortVersionString -string "$version" "$repo/packaging/Info.plist"
plutil -replace CFBundleVersion -string "$bundle_version" "$repo/packaging/Info.plist"
plutil -lint "$repo/packaging/Info.plist" >/dev/null
if [ "$dry_run" = yes ]; then
  echo "dry run: leaving Info.plist edited and uncommitted"
else
  git add packaging/Info.plist
  git commit -q -m "chore(packaging): release $version"
  echo "committed $(git rev-parse --short HEAD)"
fi

# 4. Build the bundle the normal way: one path to a signed Cue.app, used by a release and by a local run alike.
say "Building Cue.app"
"$repo/scripts/make-app.sh"

# 5. Package. `ditto` rather than `zip`, which mangles a bundle's symlinks and extended attributes and so destroys
#    the signature; the verification in step 6 is what proves it did not.
say "Packaging"
zip="$repo/dist/Cue-$version.zip"
dmg="$repo/dist/Cue-$version.dmg"
rm -f "$zip" "$dmg" "$repo/dist/SHA256SUMS"
ditto -c -k --keepParent "$repo/dist/Cue.app" "$zip"

staging=$(mktemp -d)
trap 'rm -rf "$staging" "${unpacked:-}"' EXIT
cp -R "$repo/dist/Cue.app" "$staging/Cue.app"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname "Cue $version" -srcfolder "$staging" -ov -format UDZO "$dmg"

( cd "$repo/dist" && shasum -a 256 "Cue-$version.zip" "Cue-$version.dmg" > SHA256SUMS )

# 6. Prove the archive still holds a valid, correctly signed app. Packaging is the step that silently breaks a
#    bundle, and it breaks it in the copy the user downloads, not in the one on this disk.
say "Verifying the packaged app"
unpacked=$(mktemp -d)
ditto -x -k "$zip" "$unpacked"
codesign --verify --strict --verbose=2 "$unpacked/Cue.app"
packaged=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$unpacked/Cue.app/Contents/Info.plist")
[ "$packaged" = "$version" ] || die "the packaged app says version $packaged, not $version"
echo "the unpacked copy is signed and says version $packaged"
ls -lh "$zip" "$dmg" | awk '{print $5, $9}'

# 7. Release notes: how to open an app macOS has quarantined, then what changed since the last release.
notes=$(mktemp)
{
  cat <<NOTES
Cue $version for Apple silicon, macOS 14 or later.

Download \`Cue-$version.dmg\`, open it and drag Cue to Applications.

Cue is signed ad-hoc rather than with an Apple Developer ID, so macOS quarantines it on download and refuses the
first launch. To clear that, either open System Settings > Privacy & Security and press **Open Anyway**, or run:

\`\`\`sh
xattr -dr com.apple.quarantine /Applications/Cue.app
\`\`\`

\`SHA256SUMS\` holds the checksums of both archives.

## Changes
NOTES
  previous=$(git describe --tags --abbrev=0 2>/dev/null || true)
  if [ -n "$previous" ]; then
    git log --reverse --pretty='- %s' "$previous..HEAD"
  else
    git log --reverse --pretty='- %s' -20 HEAD
  fi
} > "$notes"

if [ "$dry_run" = yes ]; then
  say "Dry run, stopping here"
  echo "the archives are in dist/ and the notes would have been:"
  echo
  cat "$notes"
  exit 0
fi

# 8. The only step that reaches outside this machine. The commit must be on origin before the draft can name
#    master as its target, and a draft creates no tag until you publish it by hand.
say "Publishing"
echo "about to push the version commit to origin/master and file a DRAFT release v$version"
if [ "$assume_yes" != yes ]; then
  read -r -p "continue? [y/N] " answer
  [ "$answer" = y ] || [ "$answer" = Y ] || die "stopped; the version commit is still local"
fi
git push origin master
gh release create "v$version" \
  --draft --target master --title "Cue $version" --notes-file "$notes" \
  "$zip" "$dmg" "$repo/dist/SHA256SUMS"

say "Done"
echo "the release is a DRAFT: nothing is public and the tag v$version does not exist yet."
echo "review it and press Publish release:"
gh release view "v$version" --json url --jq .url
