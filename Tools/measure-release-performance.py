#!/usr/bin/env python3
"""Measure cold window presentation and release-process memory on this Mac."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import platform
import re
import subprocess
import tempfile
import time


def wait_for(path: Path, process: subprocess.Popen[bytes], timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists():
            return
        if process.poll() is not None:
            raise RuntimeError(f"App exited before writing {path.name}: {process.returncode}")
        time.sleep(0.005)
    raise TimeoutError(f"Timed out waiting for {path.name}")


def p95(samples: list[float]) -> float:
    ordered = sorted(samples)
    return ordered[max(0, int(len(ordered) * 0.95 + 0.999999) - 1)]


def descendants(root_pid: int) -> list[int]:
    output = subprocess.check_output(["ps", "-axo", "pid=,ppid="], text=True)
    children: dict[int, list[int]] = {}
    for line in output.splitlines():
        pid, parent = (int(value) for value in line.split())
        children.setdefault(parent, []).append(pid)
    result = [root_pid]
    for pid in result:
        result.extend(children.get(pid, []))
    return result


def wait_for_descendant(process: subprocess.Popen[bytes], timeout: float) -> list[int]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        pids = descendants(process.pid)
        if len(pids) > 1:
            return pids
        if process.poll() is not None:
            raise RuntimeError(f"App exited before starting the sidecar: {process.returncode}")
        time.sleep(0.01)
    raise TimeoutError("Timed out waiting for the bundled sidecar process")


def resident_mebibytes(pids: list[int]) -> float:
    output = subprocess.check_output(
        ["ps", "-o", "rss=", "-p", ",".join(str(pid) for pid in pids)], text=True
    )
    values = [int(value) for value in output.split()]
    if len(values) != len(pids) or any(value <= 0 for value in values):
        raise RuntimeError("A measured app or sidecar process exited during RSS collection")
    return sum(values) / 1024


def stop_process_group(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    os.killpg(process.pid, 15)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, 9)
        process.wait(timeout=5)


def notebook_source() -> str:
    cells = "".join(
        f"\n\n@app.cell\ndef _():\n    value_{index} = {index}\n    return (value_{index},)\n"
        for index in range(100)
    )
    return (
        'import marimo\n\n__generated_with = "0.24.0"\napp = marimo.App()\n'
        + cells
        + '\n\nif __name__ == "__main__":\n    app.run()\n'
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path)
    parser.add_argument("--launch-samples", type=int, default=20)
    arguments = parser.parse_args()
    executable = arguments.app / "Contents/MacOS/MarimoNative"
    if not executable.is_file():
        raise SystemExit(f"Missing app executable: {executable}")
    if platform.machine() != "arm64":
        raise SystemExit("Release performance measurements require an arm64 Mac")

    with tempfile.TemporaryDirectory(prefix="marimonative-release-performance-") as directory:
        temporary = Path(directory)
        launch_samples: list[float] = []
        for index in range(arguments.launch_samples):
            marker = temporary / f"window-{index}.marker"
            started = time.monotonic()
            process = subprocess.Popen(
                [
                    str(executable),
                    "--performance-window-marker",
                    str(marker),
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            try:
                wait_for(marker, process, 5)
                launch_samples.append((time.monotonic() - started) * 1000)
            finally:
                stop_process_group(process)

        measured_launch_p95 = p95(launch_samples)
        print(
            f"MN-PERF-002 cold-window p95={measured_launch_p95:.3f}ms "
            f"samples={len(launch_samples)}"
        )
        if measured_launch_p95 > 2_000:
            raise SystemExit("Cold app launch p95 exceeds 2,000 ms")

        memory_window_marker = temporary / "memory-window.marker"
        cells_marker = temporary / "cells.marker"
        backend_marker = temporary / "backend.marker"
        notebook = temporary / "memory-100-cells.py"
        notebook.write_text(notebook_source(), encoding="utf-8")
        environment = os.environ.copy()
        environment["MARIMONATIVE_PERFORMANCE_NOTEBOOK"] = str(notebook)
        process = subprocess.Popen(
            [
                str(executable),
                "--performance-window-marker",
                str(memory_window_marker),
                "--performance-cells-marker",
                str(cells_marker),
                "--performance-backend-marker",
                str(backend_marker),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=environment,
            start_new_session=True,
        )
        try:
            wait_for(memory_window_marker, process, 5)
            wait_for(cells_marker, process, 15)
            wait_for(backend_marker, process, 15)
            pids = wait_for_descendant(process, 15)
            time.sleep(0.25)
            pids = descendants(process.pid)
            if process.poll() is not None or len(pids) < 2:
                raise RuntimeError("App or sidecar exited before RSS collection")
            measured_memory = resident_mebibytes(pids)
            print(
                f"MN-PERF-007 app-sidecar-rss={measured_memory:.3f}MiB "
                f"processes={len(pids)} pids={','.join(str(pid) for pid in pids)}"
            )
            if measured_memory > 350:
                raise SystemExit("App and sidecar resident memory exceeds 350 MiB")
        finally:
            stop_process_group(process)

        scroll_window_marker = temporary / "scroll-window.marker"
        scroll_marker = temporary / "scroll.marker"
        process = subprocess.Popen(
            [
                str(executable),
                "--performance-window-marker",
                str(scroll_window_marker),
                "--performance-scroll-fixture",
                "true",
                "--performance-scroll-marker",
                str(scroll_marker),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        try:
            wait_for(scroll_window_marker, process, 15)
            wait_for(scroll_marker, process, 15)
            result = scroll_marker.read_text(encoding="utf-8")
            match = re.search(r"maxMainThreadDelayMilliseconds=([0-9.]+)", result)
            if match is None:
                raise RuntimeError(f"Scroll probe failed: {result}")
            maximum_delay = float(match.group(1))
            print(
                f"MN-PERF-004 main-thread-max-delay={maximum_delay:.3f}ms "
                "cells=100 lines-per-cell=10 decoded-images=50MiB"
            )
            if maximum_delay > 100:
                raise SystemExit("Main-thread delay while scrolling exceeds 100 ms")
        finally:
            stop_process_group(process)


if __name__ == "__main__":
    main()
