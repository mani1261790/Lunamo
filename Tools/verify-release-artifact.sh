#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_root=${1:-"$project_root/.build/release-artifacts/Lunamo.app"}
verification=${2:-development}
temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT

case "$app_root" in
  /*) ;;
  *) app_root="$project_root/$app_root" ;;
esac

test -d "$app_root"
test "$(plutil -extract CFBundleIdentifier raw -o - "$app_root/Contents/Info.plist")" = \
  "dev.marimonative.app"
test "$(plutil -extract LSMinimumSystemVersion raw -o - "$app_root/Contents/Info.plist")" = "26.0"
lipo -archs "$app_root/Contents/MacOS/lunamo" | tr ' ' '\n' | grep -qx arm64
codesign --verify --deep --strict --verbose=2 "$app_root"
codesign -d --verbose=4 "$app_root" > "$temporary_directory/signature.txt" 2>&1
grep -Eq 'flags=.*runtime' "$temporary_directory/signature.txt"

codesign -d --entitlements :- "$app_root" > "$temporary_directory/entitlements.plist" 2>/dev/null
for entitlement in \
  com.apple.security.app-sandbox \
  com.apple.security.cs.allow-jit \
  com.apple.security.cs.allow-unsigned-executable-memory \
  com.apple.security.cs.disable-library-validation \
  com.apple.security.cs.allow-dyld-environment-variables
do
  if /usr/libexec/PlistBuddy -c "Print :$entitlement" \
    "$temporary_directory/entitlements.plist" >/dev/null 2>&1
  then
    echo "Forbidden entitlement is present: $entitlement" >&2
    exit 1
  fi
done

nested_count=0
while IFS= read -r candidate; do
  if file -b "$candidate" | grep -q 'Mach-O'; then
    codesign --verify --strict --verbose=2 "$candidate"
    nested_count=$((nested_count + 1))
  fi
done <<EOF
$(find "$app_root/Contents/Resources/Sidecar" -type f | LC_ALL=C sort)
EOF
test "$nested_count" -gt 0

"$project_root/Tools/verify-sidecar.sh" "$app_root/Contents/Resources/Sidecar"
"$project_root/Tools/smoke-sidecar.py" "$app_root/Contents/Resources/Sidecar" \
  --deny-network --runtime-acceptance
"$project_root/Tools/verify-release-app-flow.py" "$app_root" \
  --fixture "$project_root/Tests/Fixtures/two_cell_notebook.py"

case "$verification" in
  development) ;;
  distribution)
    grep -q '^Authority=Developer ID Application:' "$temporary_directory/signature.txt"
    ;;
  notarized)
    grep -q '^Authority=Developer ID Application:' "$temporary_directory/signature.txt"
    xcrun stapler validate "$app_root"
    spctl --assess --type execute --verbose=4 "$app_root"
    ;;
  *)
    echo "Verification must be development, distribution, or notarized" >&2
    exit 2
    ;;
esac

echo "release artifact verified: mode=$verification nested_macho=$nested_count"
