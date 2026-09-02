#!/bin/sh
set -eu

if find MarimoNative -name '*.swift' -type f -print0 | xargs -0 grep -nE 'try!|fatalError\(| as!' ; then
  echo "Forbidden Swift construct found" >&2
  exit 1
fi

oversized_files=$(find MarimoNative -name '*.swift' -type f -exec awk 'FNR == 501 { print FILENAME }' {} +)
if [ -n "$oversized_files" ]; then
  echo "Swift source exceeds 500 lines:" >&2
  echo "$oversized_files" >&2
  exit 1
fi

if grep -R -nE '^import (MarimoBackend|MarimoProcess|MarimoProtocol)$' MarimoNative/UI --include='*.swift'; then
  echo "UI imports a backend or transport module" >&2
  exit 1
fi

echo "Source policy checks passed"
