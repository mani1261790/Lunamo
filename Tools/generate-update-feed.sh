#!/bin/sh
# Run after notarizing/stapling the DMG. Does not upload or publish anything.
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
dmg=${1:?Usage: generate-update-feed.sh NOTARIZED_DMG RELEASE_TAG}
tag=${2:?Missing release tag}
case "$tag" in ''|*[!0-9A-Za-z._-]*) echo "Invalid release tag" >&2; exit 1;; esac
case "$dmg" in /*) ;; *) dmg="$PWD/$dmg";; esac
xcrun stapler validate "$dmg"
codesign --verify --strict "$dmg"
codesign -dvv "$dmg" 2>&1 | grep -q '^Authority=Developer ID Application:'
output="${MARIMONATIVE_ARTIFACT_DIR:-$project_root/.build/release-artifacts}/updates-$tag"
test ! -e "$output" || { echo "Refusing to overwrite $output" >&2; exit 1; }
mkdir -p "$output"
ditto "$dmg" "$output/$(basename "$dmg")"
tool="$project_root/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
set -- "$tool" --maximum-deltas 0 --download-url-prefix \
  "https://github.com/mani1261790/Lunamo/releases/download/$tag/"
if [ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]; then
  set -- "$@" --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE"
else
  set -- "$@" --account dev.marimonative.app
fi
"$@" "$output"
test -s "$output/appcast.xml"
echo "Prepared (not published): $output"
