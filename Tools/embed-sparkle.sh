#!/bin/sh
# Embed and sign inside-out; never use codesign --deep for signing.
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_root=${1:?Usage: embed-sparkle.sh APP SIGNING_IDENTITY}
identity=${2:?Missing signing identity}
source_framework="${SPARKLE_FRAMEWORK_PATH:-$project_root/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework}"
framework="$app_root/Contents/Frameworks/Sparkle.framework"
test -d "$source_framework"
mkdir -p "$app_root/Contents/Frameworks"
if [ -e "$framework" ]; then rm -rf "$framework"; fi
ditto "$source_framework" "$framework"
sign() {
  if [ "$identity" = "-" ]; then
    codesign --force --options runtime --sign - "$1"
  else
    codesign --force --timestamp --options runtime --sign "$identity" "$1"
  fi
}
# Sparkle's XPC services carry their own sandbox entitlements. Preserve them.
find "$framework" -depth \( -name '*.xpc' -o -name '*.app' \) -type d | while IFS= read -r item; do
  codesign --force --options runtime --preserve-metadata=entitlements \
    --sign "$identity" "$item"
done
sign "$framework/Versions/B/Autoupdate"
sign "$framework"
codesign --verify --deep --strict "$framework"
