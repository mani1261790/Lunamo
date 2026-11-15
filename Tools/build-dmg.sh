#!/bin/sh
# Production DMGs require an already notarized application.
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output="${MARIMONATIVE_ARTIFACT_DIR:-$project_root/.build/release-artifacts}"
app=${1:-"$output/Lunamo.app"}
mode=${2:-distribution}
case "$app" in /*) ;; *) app="$PWD/$app";; esac
test -d "$app"
version=$(plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist")
case "$version" in ''|*[!0-9A-Za-z.-]*) echo "Invalid version" >&2; exit 1;; esac
case "$mode" in
  distribution)
    identity=${MARIMONATIVE_CODESIGN_IDENTITY:?Set Developer ID identity}
    codesign -dvv "$app" 2>&1 | grep -q '^Authority=Developer ID Application:'
    xcrun stapler validate "$app"
    suffix=""
    ;;
  development) identity="-"; suffix="-development";;
  *) echo "Mode must be distribution or development" >&2; exit 1;;
esac
codesign --verify --deep --strict "$app"
mkdir -p "$output"
dmg="$output/Lunamo-$version$suffix.dmg"
test ! -e "$dmg" || { echo "Refusing to overwrite $dmg" >&2; exit 1; }
stage=$(mktemp -d "$output/dmg-stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT HUP INT TERM
npm ci --prefix "$project_root/Tools/dmg" --no-audit --no-fund
"$project_root/Tools/dmg/node_modules/.bin/create-dmg" \
  "$app" "$stage" --no-code-sign --no-version-in-filename --dmg-title=Lunamo
mv "$stage/Lunamo.dmg" "$dmg"
if [ "$mode" = distribution ]; then
  codesign --timestamp --sign "$identity" "$dmg"
fi
hdiutil verify "$dmg"
echo "$dmg"
