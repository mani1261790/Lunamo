#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sidecar_path=${1:-"$project_root/.build/Sidecar"}
case "$sidecar_path" in
  /*) ;;
  *) sidecar_path="$project_root/$sidecar_path" ;;
esac

python="$sidecar_path/bin/python3"
uv="$sidecar_path/bin/uv"
launcher="$sidecar_path/launch_marimo_lsp.py"
test -x "$python"
test -x "$uv"
test -f "$launcher"
test -f "$sidecar_path/protocol-lock.json"
test -s "$sidecar_path/THIRD_PARTY_NOTICES.md"
cmp "$launcher" "$project_root/MarimoNative/Resources/Sidecar/launch_marimo_lsp.py"
test "$(shasum -a 256 "$launcher" | awk '{print $1}')" = "$(plutil -extract nativeLauncherSHA256 raw -o - "$project_root/MarimoNative/Resources/Sidecar/protocol-lock.json")"
PYTHONNOUSERSITE=1 PYTHONUTF8=1 "$python" "$project_root/Tests/Contract/test_text_cells.py"
PYTHONNOUSERSITE=1 PYTHONUTF8=1 "$python" "$project_root/Tests/Contract/test_notebook_import.py"
PYTHONNOUSERSITE=1 PYTHONUTF8=1 "$python" "$project_root/Tests/Contract/test_python_completion.py"
cmp "$sidecar_path/runtime-manifest.json" "$project_root/MarimoNative/Resources/Sidecar/runtime-manifest.json"
test "$("$uv" --version | awk '{print $2}')" = "$(plutil -extract builder.uvVersion raw -o - "$sidecar_path/runtime-manifest.json")"

PYTHONNOUSERSITE=1 PYTHONUTF8=1 "$python" -I -c '
import importlib.metadata as metadata
import marimo
import marimo_lsp
import platform
import sys
assert sys.version_info[:3] == (3, 13, 15), sys.version
assert platform.machine() == "arm64", platform.machine()
assert marimo.__version__ == "0.24.0", marimo.__version__
assert metadata.version("marimo-base") == "0.24.0"
assert metadata.version("marimo-lsp") == "0.1.0"
assert "site-packages" in marimo.__file__, marimo.__file__
print("python=3.13.15 architecture=arm64 marimo=0.24.0 marimo-lsp=0.1.0")
'

if PYTHONPATH=/tmp/marimonative-invalid PYTHONNOUSERSITE=1 PYTHONUTF8=1 "$python" -I -c 'import sys; assert "/tmp/marimonative-invalid" not in sys.path'; then
  echo "user environment isolation verified"
fi

grep -q 'PYTHON SOFTWARE FOUNDATION LICENSE VERSION 2' "$sidecar_path/THIRD_PARTY_NOTICES.md"
grep -q '^## marimo-lsp 0.1.0' "$sidecar_path/THIRD_PARTY_NOTICES.md"
grep -q '^## uv$' "$sidecar_path/THIRD_PARTY_NOTICES.md"

echo "sidecar structure and versions verified"
