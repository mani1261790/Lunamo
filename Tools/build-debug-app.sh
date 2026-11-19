#!/bin/sh
set -eu

developer_dir=${DEVELOPER_DIR:-$(xcode-select -p)}
app_root=".build/Lunamo.app"
contents="$app_root/Contents"

DEVELOPER_DIR="$developer_dir" swift build
mkdir -p "$contents/MacOS" "$contents/Resources"
cp .build/debug/lunamo "$contents/MacOS/lunamo"
cp MarimoNative/Resources/Info.plist "$contents/Info.plist"
cp MarimoNative/Resources/AppIcon.icns "$contents/Resources/AppIcon.icns"
ditto MarimoNative/Resources/Licenses "$contents/Resources/Licenses"
for localization in MarimoNative/Resources/Localization/*.lproj; do
  if [ -d "$localization" ]; then
    ditto "$localization" "$contents/Resources/$(basename "$localization")"
  fi
done
for resource_bundle in .build/debug/*.bundle; do
  if [ -d "$resource_bundle" ]; then
    ditto "$resource_bundle" "$contents/Resources/$(basename "$resource_bundle")"
  fi
done
if [ -d .build/Sidecar ]; then
  ditto .build/Sidecar "$contents/Resources/Sidecar"
fi
./Tools/embed-sparkle.sh "$app_root" -
codesign --force --sign - "$app_root"
echo "$app_root"
