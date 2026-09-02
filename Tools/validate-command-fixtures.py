#!/usr/bin/env python3
"""Validate MVP command fixtures with the pinned marimo-lsp msgspec union."""

from __future__ import annotations

import json
import os
from pathlib import Path
import sys

try:
    import msgspec
except ModuleNotFoundError as error:
    raise SystemExit(
        "msgspec is unavailable; run with the bundled sidecar Python from Issue #3"
    ) from error

checkout = os.environ.get("MARIMO_LSP_CHECKOUT")
if checkout:
    sys.path.insert(0, str(Path(checkout) / "src"))

try:
    from marimo_lsp.protocol import Command
except ModuleNotFoundError as error:
    raise SystemExit(
        "marimo_lsp is unavailable; set MARIMO_LSP_CHECKOUT or use the bundled sidecar"
    ) from error

fixture_path = Path(__file__).parents[1] / "Tests/Fixtures/command_protocol_mvp.json"
fixtures = json.loads(fixture_path.read_text(encoding="utf-8"))
for fixture in fixtures:
    msgspec.json.decode(json.dumps(fixture).encode(), type=Command, strict=True)

print(f"Validated {len(fixtures)} MVP commands with pinned msgspec models")
