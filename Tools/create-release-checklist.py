#!/usr/bin/env python3
"""Create a pending checklist for evidence that cannot be automated in CI."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

import yaml


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as artifact:
        while chunk := artifact.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    mappings = yaml.safe_load((root / "Tests/Requirements.yml").read_text())
    manual_only = sorted(
        requirement
        for requirement, evidence in mappings.items()
        if evidence
        and all(
            (isinstance(item, dict) and set(item) == {"manual"})
            or (isinstance(item, str) and item.startswith("manual:"))
            for item in evidence
        )
    )
    checklist = {
        "schemaVersion": 1,
        "artifactSHA256": sha256(arguments.artifact),
        "physicalPerformanceReport": "PENDING",
        "executor": "PENDING",
        "performedAt": "PENDING",
        "requirements": {
            requirement: {"status": "pending", "note": ""}
            for requirement in manual_only
        },
    }
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(
        yaml.safe_dump(checklist, sort_keys=False, allow_unicode=True),
        encoding="utf-8",
    )
    print(
        f"Pending release checklist created: {arguments.output} "
        f"manual_only={len(manual_only)}"
    )


if __name__ == "__main__":
    main()
