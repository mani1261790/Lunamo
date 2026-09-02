#!/usr/bin/env python3
"""Verify implemented gate requirement coverage and referenced local evidence."""

from __future__ import annotations

from pathlib import Path
import re
import sys

import yaml


class UniqueKeyLoader(yaml.SafeLoader):
    pass


def construct_unique_mapping(loader: UniqueKeyLoader, node: yaml.MappingNode, deep: bool = False):
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise ValueError(f"Duplicate requirement mapping: {key}")
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
    construct_unique_mapping,
)


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    requirements_path = root / "Tests/Requirements.yml"
    mappings = yaml.load(requirements_path.read_text(), Loader=UniqueKeyLoader)
    gate_files = (
        [root / path for path in sys.argv[1:]]
        if len(sys.argv) > 1
        else sorted((root / "Tests").glob("Gate*Requirements.txt"))
    )
    required = {
        line.strip()
        for gate_file in gate_files
        for line in gate_file.read_text().splitlines()
        if line.strip()
    }
    missing = sorted(requirement for requirement in required if not mappings.get(requirement))
    if missing:
        raise SystemExit(f"Missing implemented-gate mappings: {', '.join(missing)}")

    swift_tests = "\n".join(path.read_text() for path in (root / "Tests").rglob("*.swift"))
    broken: list[str] = []
    for requirement in sorted(required):
        for evidence in mappings[requirement]:
            if isinstance(evidence, dict) and set(evidence) == {"manual"}:
                continue
            if not isinstance(evidence, str):
                broken.append(f"{requirement}: invalid evidence {evidence!r}")
                continue
            if evidence.startswith("manual:"):
                continue
            first_token = evidence.split()[0]
            if first_token.startswith(("Tools/", "Tests/", ".github/")):
                if not (root / first_token).exists():
                    broken.append(f"{requirement}: missing {first_token}")
                continue
            if "/" in evidence:
                method = evidence.rsplit("/", 1)[1]
                if re.search(rf"\bfunc\s+{re.escape(method)}\s*\(", swift_tests) is None:
                    broken.append(f"{requirement}: missing test method {method}")
                continue
            broken.append(f"{requirement}: unrecognized evidence {evidence}")
    if broken:
        raise SystemExit("Broken requirement evidence:\n" + "\n".join(broken))
    print(
        f"Implemented gate requirement evidence verified: {len(required)} requirements "
        f"across {len(gate_files)} manifests"
    )


if __name__ == "__main__":
    main()
