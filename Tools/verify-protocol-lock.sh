#!/bin/sh
set -eu

temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT

curl --fail --location --silent --show-error \
  https://raw.githubusercontent.com/marimo-team/marimo-lsp/3998b939c4e3bb09853817344ba9a976eeac8a66/src/marimo_lsp/protocol.py \
  --output "$temporary_directory/protocol.py"
curl --fail --location --silent --show-error \
  https://raw.githubusercontent.com/marimo-team/marimo/8869b186a8c1c5bc9f5e123e7df7b6677ec06b8d/marimo/_schemas/generated/notifications.yaml \
  --output "$temporary_directory/notifications.yaml"

actual_hash=$(cat "$temporary_directory/protocol.py" "$temporary_directory/notifications.yaml" | shasum -a 256 | awk '{print $1}')
expected_hash=$(plutil -extract schemaHash raw -o - MarimoNative/Resources/Sidecar/protocol-lock.json)

if [ "$actual_hash" != "$expected_hash" ]; then
  echo "Protocol schema hash mismatch" >&2
  exit 1
fi

echo "Protocol lock verified: $actual_hash"
