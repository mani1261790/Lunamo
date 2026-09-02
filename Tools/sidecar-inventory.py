#!/usr/bin/env python3
"""Print a stable inventory used to compare clean sidecar rebuilds."""

from __future__ import annotations

import hashlib
import importlib.metadata
import json
from pathlib import Path
import sys


if len(sys.argv) != 2:
    raise SystemExit("usage: sidecar-inventory.py SIDECAR_PATH")
root = Path(sys.argv[1]).resolve()
site_packages = root / "lib/python3.13/site-packages"
critical_files = [
    "launch_marimo_lsp.py",
    "protocol-lock.json",
    "runtime-manifest.json",
    "THIRD_PARTY_NOTICES.md",
]
inventory = {
    "files": {
        name: hashlib.sha256((root / name).read_bytes()).hexdigest()
        for name in critical_files
    },
    "packages": sorted(
        (distribution.metadata["Name"], distribution.version)
        for distribution in importlib.metadata.distributions(path=[str(site_packages)])
    ),
}
print(json.dumps(inventory, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
