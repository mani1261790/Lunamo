#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_path="$project_root/.build/Sidecar"
if [ "${1:-}" = "--output" ]; then
  if [ -z "${2:-}" ]; then
    echo "--output requires a path" >&2
    exit 2
  fi
  output_path=$2
elif [ "$#" -ne 0 ]; then
  echo "usage: build-sidecar.sh [--output PATH]" >&2
  exit 2
fi

case "$output_path" in
  /*) ;;
  *) output_path="$project_root/$output_path" ;;
esac

if [ -e "$output_path" ]; then
  echo "Refusing to overwrite existing output: $output_path" >&2
  exit 2
fi

manifest="$project_root/MarimoNative/Resources/Sidecar/runtime-manifest.json"
protocol_lock="$project_root/MarimoNative/Resources/Sidecar/protocol-lock.json"
launcher="$project_root/MarimoNative/Resources/Sidecar/launch_marimo_lsp.py"
python_url=$(plutil -extract python.url raw -o - "$manifest")
python_hash=$(plutil -extract python.sha256 raw -o - "$manifest")
python_license_url=$(plutil -extract python.licenseURL raw -o - "$manifest")
python_license_hash=$(plutil -extract python.licenseSHA256 raw -o - "$manifest")
lsp_url=$(plutil -extract marimoLSP.url raw -o - "$manifest")
lsp_hash=$(plutil -extract marimoLSP.sha256 raw -o - "$manifest")
lock_hash=$(plutil -extract marimoLSP.uvLockSHA256 raw -o - "$manifest")
expected_uv=$(plutil -extract builder.uvVersion raw -o - "$manifest")
uv_url=$(plutil -extract builder.url raw -o - "$manifest")
uv_hash=$(plutil -extract builder.sha256 raw -o - "$manifest")
uv_license_url=$(plutil -extract builder.licenseURL raw -o - "$manifest")
uv_license_hash=$(plutil -extract builder.licenseSHA256 raw -o - "$manifest")

build_root=$(mktemp -d)
cleanup() {
  if [ -d "$build_root" ]; then
    find "$build_root" -depth -delete
  fi
}
trap cleanup EXIT HUP INT TERM
python_archive="$build_root/python.tar.gz"
lsp_archive="$build_root/marimo-lsp.tar.gz"
uv_archive="$build_root/uv.tar.gz"
python_license="$build_root/CPYTHON_LICENSE.txt"
uv_license="$build_root/UV_LICENSE.txt"

curl --fail --location --silent --show-error "$python_url" --output "$python_archive"
echo "$python_hash  $python_archive" | shasum -a 256 --check --status
curl --fail --location --silent --show-error "$python_license_url" --output "$python_license"
echo "$python_license_hash  $python_license" | shasum -a 256 --check --status
curl --fail --location --silent --show-error "$lsp_url" --output "$lsp_archive"
echo "$lsp_hash  $lsp_archive" | shasum -a 256 --check --status
curl --fail --location --silent --show-error "$uv_url" --output "$uv_archive"
echo "$uv_hash  $uv_archive" | shasum -a 256 --check --status
curl --fail --location --silent --show-error "$uv_license_url" --output "$uv_license"
echo "$uv_license_hash  $uv_license" | shasum -a 256 --check --status

mkdir -p "$build_root/python" "$build_root/lsp" "$build_root/uv"
tar -xzf "$python_archive" -C "$build_root/python" --strip-components=1
tar -xzf "$lsp_archive" -C "$build_root/lsp" --strip-components=1
tar -xzf "$uv_archive" -C "$build_root/uv" --strip-components=1
uv="$build_root/uv/uv"
actual_uv=$("$uv" --version | awk '{print $2}')
if [ "$actual_uv" != "$expected_uv" ]; then
  echo "Pinned uv version mismatch: expected $expected_uv, found $actual_uv" >&2
  exit 1
fi
cp "$uv" "$build_root/python/bin/uv"

actual_lock_hash=$(shasum -a 256 "$build_root/lsp/uv.lock" | awk '{print $1}')
if [ "$actual_lock_hash" != "$lock_hash" ]; then
  echo "Pinned uv.lock hash mismatch" >&2
  exit 1
fi

(cd "$build_root/lsp" && "$uv" export --frozen --no-dev --no-emit-project --format requirements.txt --output-file "$build_root/requirements.txt" --quiet)
"$uv" pip install --python "$build_root/python/bin/python3" --require-hashes --requirements "$build_root/requirements.txt" --quiet

mkdir -p "$build_root/wheel"
SOURCE_DATE_EPOCH=315532800 "$uv" build --wheel --python "$build_root/python/bin/python3" --no-python-downloads --no-cache --out-dir "$build_root/wheel" "$build_root/lsp" --quiet
lsp_wheel="$build_root/wheel/marimo_lsp-0.1.0-py3-none-any.whl"
test -f "$lsp_wheel"
"$uv" pip install --python "$build_root/python/bin/python3" --no-deps "$lsp_wheel" --quiet
direct_url="$build_root/python/lib/python3.13/site-packages/marimo_lsp-0.1.0.dist-info/direct_url.json"
if [ -f "$direct_url" ]; then
  find "$direct_url" -delete
fi

cp "$launcher" "$build_root/python/launch_marimo_lsp.py"
cp "$manifest" "$build_root/python/runtime-manifest.json"
cp "$protocol_lock" "$build_root/python/protocol-lock.json"
PYTHONNOUSERSITE=1 PYTHONUTF8=1 "$build_root/python/bin/python3" "$project_root/Tools/generate-third-party-notices.py" "$build_root/python/THIRD_PARTY_NOTICES.md" "$python_license" "$build_root/lsp/LICENSE" "$uv_license"

mkdir -p "$(dirname "$output_path")"
mv "$build_root/python" "$output_path"
echo "$output_path"
