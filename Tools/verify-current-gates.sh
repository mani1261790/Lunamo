#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

if [ -z "${DEVELOPER_DIR:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ]; then
  for candidate in \
    /Applications/Xcode.app/Contents/Developer \
    /Applications/Xcode-beta.app/Contents/Developer \
    /Applications/Xcode_*.app/Contents/Developer
  do
    if [ -x "$candidate/usr/bin/xcodebuild" ]; then
      DEVELOPER_DIR=$candidate
      export DEVELOPER_DIR
      break
    fi
  done
fi
if ! xcrun --find xcodebuild >/dev/null 2>&1; then
  echo "A full Xcode installation is required; set DEVELOPER_DIR to its Contents/Developer directory" >&2
  exit 1
fi

test -x .build/Sidecar/bin/python3
./Tools/verify-sidecar.sh
swift build
swift test
xcrun swift-format lint --recursive --strict MarimoNative Tests Package.swift
./Tools/verify-source-policy.sh
./Tools/verify-protocol-lock.sh
.build/Sidecar/bin/python3 -I Tools/verify-requirements.py --all-must
./Tools/smoke-sidecar.py .build/Sidecar --deny-network --runtime-acceptance
./Tools/build-debug-app.sh >/dev/null
./Tools/verify-release-app-flow.py .build/MarimoNative.app \
  --fixture Tests/Fixtures/two_cell_notebook.py

echo "Implemented gates local verification passed"
