#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
artifact_directory=${MARIMONATIVE_ARTIFACT_DIR:-"$project_root/.build/release-artifacts"}
app_root=${1:-"$artifact_directory/Lunamo.app"}
case "$app_root" in
  /*) ;;
  *) app_root="$project_root/$app_root" ;;
esac

version=$(plutil -extract CFBundleShortVersionString raw -o - "$app_root/Contents/Info.plist")
submission="$artifact_directory/Lunamo-$version-submission.zip"
artifact="$artifact_directory/Lunamo-$version.zip"
notary_result="$artifact_directory/notarization.json"


"$project_root/Tools/verify-protocol-lock.sh"
"$project_root/Tools/verify-release-artifact.sh" "$app_root" distribution
rm -f "$submission" "$artifact" "$notary_result"
ditto -c -k --sequesterRsrc --keepParent "$app_root" "$submission"

set -- xcrun notarytool submit "$submission" --wait --timeout 30m --output-format json
if [ -n "${MARIMONATIVE_NOTARY_PROFILE:-}" ]; then
  set -- "$@" --keychain-profile "$MARIMONATIVE_NOTARY_PROFILE"
elif [ -n "${MARIMONATIVE_NOTARY_KEY:-}" ] && [ -n "${MARIMONATIVE_NOTARY_KEY_ID:-}" ]; then
  set -- "$@" --key "$MARIMONATIVE_NOTARY_KEY" --key-id "$MARIMONATIVE_NOTARY_KEY_ID"
  if [ -n "${MARIMONATIVE_NOTARY_ISSUER_ID:-}" ]; then
    set -- "$@" --issuer "$MARIMONATIVE_NOTARY_ISSUER_ID"
  fi
else
  echo "Set MARIMONATIVE_NOTARY_PROFILE or the notary API key variables" >&2
  exit 1
fi

"$@" > "$notary_result"
status=$(plutil -extract status raw -o - "$notary_result")
if [ "$status" != "Accepted" ]; then
  echo "Apple Notary Service returned status: $status" >&2
  exit 1
fi

xcrun stapler staple "$app_root"
"$project_root/Tools/verify-release-artifact.sh" "$app_root" notarized
ditto -c -k --sequesterRsrc --keepParent "$app_root" "$artifact"
artifact_hash=$(shasum -a 256 "$artifact" | awk '{print $1}')
echo "notarized release artifact: $artifact sha256=$artifact_hash"
