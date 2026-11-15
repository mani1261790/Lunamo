#!/bin/sh
set -eu
dmg=${1:?Usage: notarize-dmg.sh DMG}
test -f "$dmg"
codesign --verify --strict "$dmg"
codesign -dvv "$dmg" 2>&1 | grep -q '^Authority=Developer ID Application:'
set -- xcrun notarytool submit "$dmg" --wait --timeout 30m --output-format json
if [ -n "${MARIMONATIVE_NOTARY_PROFILE:-}" ]; then
  set -- "$@" --keychain-profile "$MARIMONATIVE_NOTARY_PROFILE"
elif [ -n "${MARIMONATIVE_NOTARY_KEY:-}" ] && [ -n "${MARIMONATIVE_NOTARY_KEY_ID:-}" ]; then
  set -- "$@" --key "$MARIMONATIVE_NOTARY_KEY" --key-id "$MARIMONATIVE_NOTARY_KEY_ID"
  if [ -n "${MARIMONATIVE_NOTARY_ISSUER_ID:-}" ]; then
    set -- "$@" --issuer "$MARIMONATIVE_NOTARY_ISSUER_ID"
  fi
else
  echo "Set MARIMONATIVE_NOTARY_PROFILE or Notary API key variables" >&2
  exit 1
fi
"$@" > "$dmg.notarization.json"
test "$(plutil -extract status raw -o - "$dmg.notarization.json")" = Accepted
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg"
shasum -a 256 "$dmg"
