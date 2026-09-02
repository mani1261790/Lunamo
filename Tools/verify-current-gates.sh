#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

test -x .build/Sidecar/bin/python3
./Tools/verify-sidecar.sh
swift build
swift test
xcrun swift-format lint --recursive --strict MarimoNative Tests Package.swift
./Tools/verify-source-policy.sh
./Tools/verify-protocol-lock.sh
.build/Sidecar/bin/python3 -I Tools/verify-requirements.py --all-must
./Tools/smoke-sidecar.py .build/Sidecar --deny-network

echo "Implemented gates local verification passed"
