#!/usr/bin/env python3
"""Verify implemented gate requirement coverage and referenced local evidence."""

from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
import math
from pathlib import Path
import re

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


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("gate_files", nargs="*", type=Path)
    parser.add_argument(
        "--all-must",
        action="store_true",
        help="Require a mapping for every MUST and MUST NOT in the strict specification.",
    )
    parser.add_argument(
        "--release-checklist",
        type=Path,
        help="Verify completed manual-only evidence in a release checklist.",
    )
    parser.add_argument(
        "--artifact",
        type=Path,
        help="Artifact whose SHA-256 must match the release checklist.",
    )
    return parser.parse_args()


def specification_requirements(root: Path) -> set[str]:
    specification = root / "MarimoNative_Strict_Specification_v1.0.md"
    pattern = re.compile(r"^(MN-[A-Z]+-\d{3}[A-Z]?) MUST(?: NOT)?\s*$")
    return {
        match.group(1)
        for line in specification.read_text().splitlines()
        if (match := pattern.match(line))
    }


def is_manual_evidence(evidence: object) -> bool:
    return (
        isinstance(evidence, dict)
        and set(evidence) == {"manual"}
        and isinstance(evidence["manual"], str)
    ) or (isinstance(evidence, str) and evidence.startswith("manual:"))


def manual_only_requirements(mappings: dict[str, list[object]]) -> set[str]:
    return {
        requirement
        for requirement, evidence in mappings.items()
        if evidence and all(is_manual_evidence(item) for item in evidence)
    }


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as artifact:
        while chunk := artifact.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def verify_physical_performance(report_path: Path, expected_hash: str) -> None:
    report = json.loads(report_path.read_text())
    if report.get("schemaVersion") != 1 or report.get("artifactSHA256") != expected_hash:
        raise SystemExit("Physical performance report does not match this DMG")
    host = report.get("host", {})
    if (host.get("architecture") != "arm64" or host.get("virtualMachine") is not False
            or not str(host.get("model", "")).startswith("Mac")):
        raise SystemExit("Performance qualification requires a physical Apple Silicon Mac")
    try:
        timestamp = datetime.fromisoformat(str(report.get("performedAt", "")))
        if timestamp.tzinfo is None:
            raise ValueError("Missing timezone")
    except ValueError as error:
        raise SystemExit("Physical performance report has no valid timestamp") from error
    metrics = report.get("metrics", {})
    limits = {"launchP95Milliseconds": 2000, "residentMiB": 350,
              "scrollMaxMilliseconds": 100}
    samples = metrics.get("launchSamples")
    if (isinstance(samples, bool) or not isinstance(samples, (int, float))
            or not math.isfinite(samples) or samples < 20 or not float(samples).is_integer()):
        raise SystemExit("Physical performance requires at least 20 launch samples")
    for name, limit in limits.items():
        value = metrics.get(name)
        if (isinstance(value, bool) or not isinstance(value, (int, float))
                or not math.isfinite(value) or not 0 <= value <= limit):
            raise SystemExit(f"Physical performance requirement failed: {name} <= {limit}")


def verify_release_checklist(
    checklist_path: Path,
    artifact_path: Path | None,
    manual_requirements: set[str],
) -> None:
    if artifact_path is None:
        raise SystemExit("--release-checklist requires --artifact")
    checklist = yaml.safe_load(checklist_path.read_text())
    if not isinstance(checklist, dict) or checklist.get("schemaVersion") != 1:
        raise SystemExit("Release checklist must use schemaVersion 1")

    executor = checklist.get("executor")
    if not isinstance(executor, str) or not executor.strip() or executor == "PENDING":
        raise SystemExit("Release checklist executor is missing")
    performed_at = checklist.get("performedAt")
    try:
        parsed_time = datetime.fromisoformat(str(performed_at).replace("Z", "+00:00"))
    except ValueError as error:
        raise SystemExit("Release checklist performedAt must be an ISO-8601 timestamp") from error
    if parsed_time.tzinfo is None:
        raise SystemExit("Release checklist performedAt must include a timezone")

    expected_hash = sha256(artifact_path)
    if checklist.get("artifactSHA256") != expected_hash:
        raise SystemExit("Release checklist artifactSHA256 does not match the supplied artifact")

    report_name = checklist.get("physicalPerformanceReport")
    if not isinstance(report_name, str) or report_name in ("", "PENDING"):
        raise SystemExit("A passing physical-Mac performance report is required before publication")
    verify_physical_performance(checklist_path.parent / report_name, expected_hash)

    entries = checklist.get("requirements")
    if not isinstance(entries, dict):
        raise SystemExit("Release checklist requirements must be a mapping")
    incomplete = sorted(
        requirement
        for requirement in manual_requirements
        if not isinstance(entries.get(requirement), dict)
        or entries[requirement].get("status") != "verified"
        or not str(entries[requirement].get("note", "")).strip()
    )
    if incomplete:
        raise SystemExit(
            "Manual-only release evidence is incomplete: " + ", ".join(incomplete)
        )
    print(
        f"Release checklist verified: {len(manual_requirements)} manual-only requirements, "
        f"executor={executor}, performedAt={performed_at}, sha256={expected_hash}"
    )


def main() -> None:
    arguments = parse_arguments()
    root = Path(__file__).resolve().parent.parent
    requirements_path = root / "Tests/Requirements.yml"
    mappings = yaml.load(requirements_path.read_text(), Loader=UniqueKeyLoader)
    if not isinstance(mappings, dict):
        raise SystemExit("Tests/Requirements.yml must contain a mapping")
    gate_files = [root / path for path in arguments.gate_files]
    if not gate_files and not arguments.all_must:
        gate_files = sorted((root / "Tests").glob("Gate*Requirements.txt"))
    required = specification_requirements(root) if arguments.all_must else set()
    required.update(
        line.strip()
        for gate_file in gate_files
        for line in gate_file.read_text().splitlines()
        if line.strip()
    )
    missing = sorted(requirement for requirement in required if not mappings.get(requirement))
    if missing:
        raise SystemExit(f"Missing implemented-gate mappings: {', '.join(missing)}")

    swift_tests = "\n".join(path.read_text() for path in (root / "Tests").rglob("*.swift"))
    broken: list[str] = []
    for requirement in sorted(required):
        for evidence in mappings[requirement]:
            if is_manual_evidence(evidence):
                continue
            if not isinstance(evidence, str):
                broken.append(f"{requirement}: invalid evidence {evidence!r}")
                continue
            if evidence.startswith("manual:"):
                continue
            first_token = evidence.split()[0]
            if first_token.startswith(("MarimoNative/", "Tools/", "Tests/", ".github/")):
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
    if arguments.release_checklist is not None:
        verify_release_checklist(
            root / arguments.release_checklist,
            root / arguments.artifact if arguments.artifact is not None else None,
            manual_only_requirements(mappings),
        )
    print(
        f"Implemented gate requirement evidence verified: {len(required)} requirements "
        f"across {len(gate_files)} manifests"
    )


if __name__ == "__main__":
    main()
