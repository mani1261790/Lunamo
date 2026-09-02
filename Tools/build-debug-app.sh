#!/bin/sh
set -eu

developer_dir=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
app_root=".build/MarimoNative.app"
contents="$app_root/Contents"

DEVELOPER_DIR="$developer_dir" swift build
mkdir -p "$contents/MacOS" "$contents/Resources"
cp .build/debug/MarimoNative "$contents/MacOS/MarimoNative"
cp MarimoNative/Resources/Info.plist "$contents/Info.plist"
if [ -d .build/Sidecar ]; then
  ditto .build/Sidecar "$contents/Resources/Sidecar"
fi
codesign --force --sign - "$app_root"
echo "$app_root"
