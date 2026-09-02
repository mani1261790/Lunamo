#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
developer_dir=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
identity=${MARIMONATIVE_CODESIGN_IDENTITY:-}
artifact_directory=${MARIMONATIVE_ARTIFACT_DIR:-"$project_root/.build/release-artifacts"}
app_root="$artifact_directory/MarimoNative.app"
contents="$app_root/Contents"
entitlements="$project_root/MarimoNative/Resources/MarimoNative.entitlements"

if [ -z "$identity" ]; then
  echo "MARIMONATIVE_CODESIGN_IDENTITY must name a signing identity" >&2
  exit 1
fi

"$project_root/Tools/verify-sidecar.sh" "$project_root/.build/Sidecar"
# Apple Swift 6.2.3 currently aborts in the optimizer while compiling SwiftSoup 2.13.5.
# Keep the Release compilation condition (not DEBUG) while disabling that failing optimizer pass.
DEVELOPER_DIR="$developer_dir" swift build --package-path "$project_root" -c release -Xswiftc -Onone

mkdir -p "$artifact_directory"
if [ -e "$app_root" ]; then
  rm -rf "$app_root"
fi
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$project_root/.build/release/MarimoNative" "$contents/MacOS/MarimoNative"
cp "$project_root/MarimoNative/Resources/Info.plist" "$contents/Info.plist"
for localization in "$project_root"/MarimoNative/Resources/Localization/*.lproj; do
  if [ -d "$localization" ]; then
    ditto "$localization" "$contents/Resources/$(basename "$localization")"
  fi
done
for resource_bundle in "$project_root"/.build/release/*.bundle; do
  if [ -d "$resource_bundle" ]; then
    ditto "$resource_bundle" "$contents/Resources/$(basename "$resource_bundle")"
  fi
done
ditto "$project_root/.build/Sidecar" "$contents/Resources/Sidecar"

sign_item() {
  item=$1
  if [ "$identity" = "-" ]; then
    codesign --force --options runtime --sign - "$item"
  else
    codesign --force --timestamp --options runtime --sign "$identity" "$item"
  fi
}

nested_count=0
while IFS= read -r candidate; do
  if file -b "$candidate" | grep -q 'Mach-O'; then
    sign_item "$candidate"
    nested_count=$((nested_count + 1))
  fi
done <<EOF
$(find "$contents/Resources/Sidecar" -type f | LC_ALL=C sort)
EOF

if [ "$identity" = "-" ]; then
  codesign --force --options runtime --entitlements "$entitlements" --sign - "$app_root"
else
  codesign --force --timestamp --options runtime --entitlements "$entitlements" \
    --sign "$identity" "$app_root"
fi

codesign --verify --deep --strict --verbose=2 "$app_root"
echo "release app signed: $app_root nested_macho=$nested_count"
