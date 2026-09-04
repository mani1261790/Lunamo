#!/usr/bin/env python3
"""Generate notices from distributions installed in the sidecar runtime."""

from __future__ import annotations

from importlib import metadata
from pathlib import Path
import sys


def field(distribution: metadata.Distribution, name: str) -> str:
    value = distribution.metadata.get(name)
    return value.strip() if value else "Not declared"


def license_files(distribution: metadata.Distribution) -> list[Path]:
    result: list[Path] = []
    for item in distribution.files or []:
        lowered = item.name.lower()
        if lowered.startswith(("license", "copying", "notice")):
            path = Path(distribution.locate_file(item))
            if path.is_file() and path.stat().st_size <= 256 * 1024:
                result.append(path)
    return result


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit(
            "usage: generate-third-party-notices.py OUTPUT CPYTHON_LICENSE MARIMO_LSP_LICENSE UV_LICENSE"
        )
    output = Path(sys.argv[1])
    cpython_license = Path(sys.argv[2]).read_text(encoding="utf-8")
    marimo_lsp_license = Path(sys.argv[3]).read_text(encoding="utf-8")
    uv_license = Path(sys.argv[4]).read_text(encoding="utf-8")
    lines = [
        "# Third-Party Notices",
        "",
        "This file is generated from the exact distributions bundled with MarimoNative.",
        "",
        "## CPython",
        "",
        f"Version: {sys.version.split()[0]}",
        "Source: https://www.python.org/",
        "License: Python Software Foundation License Version 2",
        "",
        "```text",
        cpython_license.rstrip(),
        "```",
        "",
        "## uv",
        "",
        "Source: https://github.com/astral-sh/uv",
        "License: MIT",
        "",
        "```text",
        uv_license.rstrip(),
        "```",
        "",
    ]
    for distribution in sorted(metadata.distributions(), key=lambda item: item.metadata["Name"].lower()):
        name = distribution.metadata["Name"]
        license_name = "Apache-2.0" if name == "marimo-lsp" else (
            field(distribution, "License-Expression")
            if field(distribution, "License-Expression") != "Not declared"
            else field(distribution, "License")
        )
        lines.extend(
            [
                f"## {name} {distribution.version}",
                "",
                f"Homepage: {field(distribution, 'Home-page')}",
                f"License: {license_name}",
                "",
            ]
        )
        if name == "marimo-lsp":
            lines.extend(
                ["### LICENSE", "", "```text", marimo_lsp_license.rstrip(), "```", ""]
            )
        for path in license_files(distribution):
            try:
                text = path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue
            lines.extend([f"### {path.name}", "", "```text", text.rstrip(), "```", ""])
    output.write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
