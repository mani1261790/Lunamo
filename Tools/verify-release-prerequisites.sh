#!/bin/sh
set -eu

identity=${MARIMONATIVE_CODESIGN_IDENTITY:-}
profile=${MARIMONATIVE_NOTARY_PROFILE:-}
key=${MARIMONATIVE_NOTARY_KEY:-}
key_id=${MARIMONATIVE_NOTARY_KEY_ID:-}
issuer_id=${MARIMONATIVE_NOTARY_ISSUER_ID:-}

if [ "$(uname -m)" != "arm64" ]; then
  echo "Release qualification requires an arm64 Mac" >&2
  exit 1
fi
major_version=$(sw_vers -productVersion | cut -d. -f1)
if [ "$major_version" -lt 26 ]; then
  echo "Release qualification requires macOS 26 or later" >&2
  exit 1
fi
if [ -z "$identity" ]; then
  echo "MARIMONATIVE_CODESIGN_IDENTITY is missing" >&2
  exit 1
fi
identity_line=$(security find-identity -v -p codesigning | grep -F "$identity" || true)
if ! printf '%s\n' "$identity_line" | grep -q 'Developer ID Application:'; then
  echo "The selected identity is not a Developer ID Application identity" >&2
  exit 1
fi

if [ -n "$profile" ]; then
  echo "Release prerequisites verified: Developer ID and notary keychain profile"
  exit 0
fi
if [ -z "$key" ] || [ ! -f "$key" ] || [ -z "$key_id" ] || [ -z "$issuer_id" ]; then
  echo "Notary credentials are incomplete; set a keychain profile or API key, key ID, and issuer ID" >&2
  exit 1
fi

case "$(stat -f '%Lp' "$key")" in
  600|400) ;;
  *)
    echo "Notary private key permissions must be 600 or 400" >&2
    exit 1
    ;;
esac

echo "Release prerequisites verified: Developer ID and Notary API key"
