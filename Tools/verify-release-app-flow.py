#!/usr/bin/env python3
"""Exercise open, edit, save, execute, and cleanup through the packaged app."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time


SANDBOX_PROFILE = """(version 1)
(allow default)
(deny network*)
(allow network-bind (local ip "localhost:*"))
(allow network-inbound (local ip "localhost:*"))
(allow network-outbound (remote ip "localhost:*"))
"""


def process_group_members(process_group_id: int) -> set[int]:
    output = subprocess.check_output(["ps", "-axo", "pid=,pgid="], text=True)
    return {
        int(values[0])
        for line in output.splitlines()
        if len(values := line.split()) == 2 and values[1] == str(process_group_id)
    }


def terminate_process_group(process: subprocess.Popen[bytes]) -> None:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=2)


def wait_for_marker(marker: Path, process: subprocess.Popen[bytes], timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if marker.is_file():
            return
        if process.poll() is not None:
            raise RuntimeError(f"App exited before writing acceptance result: {process.returncode}")
        time.sleep(0.025)
    raise TimeoutError("Timed out waiting for packaged app acceptance result")


def wait_for_process_group_exit(process_group_id: int, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not process_group_members(process_group_id):
            return
        time.sleep(0.025)
    remaining = sorted(process_group_members(process_group_id))
    if remaining:
        raise RuntimeError(f"Packaged app left processes behind: {remaining}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("--fixture", required=True, type=Path)
    arguments = parser.parse_args()
    app = arguments.app.resolve()
    executable = app / "Contents/MacOS/lunamo"
    python = app / "Contents/Resources/Sidecar/bin/python3"
    if not executable.is_file() or not python.is_file():
        raise SystemExit(f"Incomplete release app: {app}")

    with tempfile.TemporaryDirectory(prefix="marimonative-release-app-flow-") as directory:
        temporary = Path(directory).resolve()
        notebook = temporary / "acceptance.py"
        marker = temporary / "result.json"
        shutil.copy2(arguments.fixture.resolve(), notebook)
        environment = os.environ.copy()
        environment["HOME"] = str(temporary)
        environment["CFFIXED_USER_HOME"] = str(temporary)
        command = [
            "/usr/bin/sandbox-exec",
            "-p",
            SANDBOX_PROFILE,
            str(executable),
            "--release-acceptance-notebook",
            str(notebook),
            "--release-acceptance-python",
            str(python),
            "--release-acceptance-marker",
            str(marker),
        ]
        process = subprocess.Popen(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            env=environment,
            start_new_session=True,
        )
        try:
            wait_for_marker(marker, process, 90)
            result = json.loads(marker.read_text(encoding="utf-8"))
            if result.get("status") != "passed" or not all(
                result.get(key) is True
                for key in (
                    "open",
                    "edit",
                    "save",
                    "pythonSelection",
                    "trustPrompt",
                    "execute",
                    "cleanup",
                )
            ):
                raise RuntimeError(f"Packaged app acceptance failed: {result}")
            if result.get("output") != "43":
                raise RuntimeError(f"Packaged app returned unexpected output: {result}")
            if "first = 21" not in notebook.read_text(encoding="utf-8"):
                raise RuntimeError("Packaged app did not persist the native edit")
            try:
                return_code = process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                terminate_process_group(process)
                raise RuntimeError("Packaged app did not terminate after acceptance")
            if return_code != 0:
                raise RuntimeError(f"Packaged app exited with {return_code}")
            wait_for_process_group_exit(process.pid, 5)
        except Exception:
            terminate_process_group(process)
            assert process.stderr is not None
            error_output = process.stderr.read().decode(errors="replace")
            if error_output:
                print(error_output, file=sys.stderr)
            raise

        print(
            "packaged app flow passed: open/edit/save/python-selection/"
            "trust/execute/output-43/cleanup; external-network-denied=True"
        )


if __name__ == "__main__":
    main()
