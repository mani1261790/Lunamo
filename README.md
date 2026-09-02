# MarimoNative

MarimoNative is a native macOS client for opening, editing, and running marimo notebooks. The implementation follows `MarimoNative_Strict_Specification_v1.0.md`.

## Local development

The project requires macOS 26 or later, Apple Silicon, and Swift 6.2 or later.

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift-format lint --recursive --strict MarimoNative Tests Package.swift
./Tools/verify-source-policy.sh
./Tools/build-sidecar.sh
./Tools/verify-sidecar.sh
./Tools/smoke-sidecar.py .build/Sidecar --deny-network
./Tools/build-debug-app.sh
./Tools/verify-gate-a.sh
./Tools/verify-current-gates.sh
```

`verify-gate-a.sh` preserves the frozen Gate A check. `verify-current-gates.sh` verifies every implemented gate manifest and is the command used by CI.

The current Swift Package executable is the build and test foundation. Gate F adds the signed application bundle and distribution pipeline.
