#!/usr/bin/env python3
"""Exercise the bundled LSP sidecar over stdio, optionally without network."""

from __future__ import annotations

import argparse
import json
import os
import select
import signal
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path
from typing import Any, Callable


class LSPClient:
    def __init__(self, process: subprocess.Popen[bytes]) -> None:
        self.process = process
        self.kernel_notifications: list[dict[str, Any]] = []

    def send(self, message: dict[str, Any]) -> None:
        assert self.process.stdin is not None
        payload = json.dumps(message, separators=(",", ":")).encode()
        self.process.stdin.write(f"Content-Length: {len(payload)}\r\n\r\n".encode() + payload)
        self.process.stdin.flush()

    def response(self, request_id: int, timeout: float = 15.0) -> dict[str, Any]:
        while True:
            message = self._read(timeout)
            if message.get("id") == request_id and "method" not in message:
                return message
            if "id" in message and "method" in message:
                self._reply_to_server(message)
            elif message.get("method") == "marimo/kernelNotification":
                self.kernel_notifications.append(message["params"])

    def kernel_notification(
        self,
        operation: str,
        notebook_uri: str,
        timeout: float = 30.0,
        after: int = 0,
        predicate: Callable[[dict[str, Any]], bool] | None = None,
    ) -> tuple[int, dict[str, Any]]:
        deadline = time.monotonic() + timeout
        while True:
            for index, notification in enumerate(
                self.kernel_notifications[after:], start=after
            ):
                if (
                    notification.get("notebookUri") == notebook_uri
                    and notification.get("notification", {}).get("op") == operation
                    and (
                        predicate is None
                        or predicate(notification.get("notification", {}))
                    )
                ):
                    return index, notification
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(f"Timed out waiting for kernel operation {operation}")
            message = self._read(remaining)
            if "id" in message and "method" in message:
                self._reply_to_server(message)
            elif message.get("method") == "marimo/kernelNotification":
                self.kernel_notifications.append(message["params"])

    def _reply_to_server(self, request: dict[str, Any]) -> None:
        method = request["method"]
        if method == "workspace/configuration":
            items = request.get("params", {}).get("items", [])
            result: Any = [None] * len(items)
        else:
            result = None
        self.send({"jsonrpc": "2.0", "id": request["id"], "result": result})

    def _read(self, timeout: float) -> dict[str, Any]:
        assert self.process.stdout is not None
        deadline = time.monotonic() + timeout
        headers: dict[str, str] = {}
        while True:
            line = self._readline(deadline)
            if line == b"\r\n":
                break
            name, value = line.decode("ascii").split(":", 1)
            headers[name.lower()] = value.strip()
        length = int(headers["content-length"])
        payload = self._read_exact(length, deadline)
        return json.loads(payload)

    def _readline(self, deadline: float) -> bytes:
        line = bytearray()
        while not line.endswith(b"\n"):
            line.extend(self._read_exact(1, deadline))
        return bytes(line)

    def _read_exact(self, size: int, deadline: float) -> bytes:
        assert self.process.stdout is not None
        data = bytearray()
        while len(data) < size:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("Timed out reading LSP response")
            ready, _, _ = select.select([self.process.stdout], [], [], remaining)
            if not ready:
                raise TimeoutError("Timed out reading LSP response")
            chunk = os.read(self.process.stdout.fileno(), size - len(data))
            if not chunk:
                raise EOFError("LSP stdout closed")
            data.extend(chunk)
        return bytes(data)


def launch(sidecar: Path, deny_network: bool) -> subprocess.Popen[bytes]:
    python = sidecar / "bin/python3"
    launcher = sidecar / "launch_marimo_lsp.py"
    command = [str(python), str(launcher)]
    if deny_network:
        profile = """(version 1)
(allow default)
(deny network*)
(allow network-bind (local ip "localhost:*"))
(allow network-inbound (local ip "localhost:*"))
(allow network-outbound (remote ip "localhost:*"))
"""
        command = ["/usr/bin/sandbox-exec", "-p", profile, *command]
    environment = {
        "HOME": os.environ.get("HOME", "/tmp"),
        "LANG": "en_US.UTF-8",
        "PATH": "/usr/bin:/bin",
        "PYTHONNOUSERSITE": "1",
        "PYTHONUTF8": "1",
        "TMPDIR": os.environ.get("TMPDIR", "/tmp"),
    }
    return subprocess.Popen(
        command,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=environment,
        start_new_session=True,
    )


def descendants(root_pid: int) -> set[int]:
    output = subprocess.check_output(["ps", "-axo", "pid=,ppid="], text=True)
    children: dict[int, list[int]] = {}
    for line in output.splitlines():
        pid, parent = (int(value) for value in line.split())
        children.setdefault(parent, []).append(pid)
    result = [root_pid]
    for pid in result:
        result.extend(children.get(pid, []))
    return set(result)


def wait_for_descendants(root_pid: int, expected: set[int], timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if descendants(root_pid) <= expected:
            return
        time.sleep(0.025)
    remaining = sorted(descendants(root_pid) - expected)
    if not remaining:
        return
    raise RuntimeError(f"Kernel processes remained after shutdown: {remaining}")


def process_group_members(process_group_id: int) -> set[int]:
    output = subprocess.check_output(["ps", "-axo", "pid=,pgid="], text=True)
    return {
        int(values[0])
        for line in output.splitlines()
        if (values := line.split())[1] == str(process_group_id)
    }


def wait_for_process_group_exit(process_group_id: int, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not process_group_members(process_group_id):
            return
        time.sleep(0.025)
    remaining = sorted(process_group_members(process_group_id))
    if remaining:
        raise RuntimeError(f"Sidecar process group remained after shutdown: {remaining}")


def terminate_process_group(process: subprocess.Popen[bytes]) -> None:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=2)
    wait_for_process_group_exit(process.pid, 2)


def check_response(response: dict[str, Any], request_id: int) -> Any:
    if "error" in response:
        raise RuntimeError(f"request {request_id} failed: {response['error']}")
    return response["result"]


def runtime_acceptance(
    client: LSPClient,
    process: subprocess.Popen[bytes],
    sidecar: Path,
    document: dict[str, Any],
    source: str,
) -> None:
    baseline_processes = descendants(process.pid)
    python = (sidecar / "bin/python3").resolve()
    cells: list[dict[str, str]] = []
    notebook_cells: list[dict[str, Any]] = []
    text_documents: list[dict[str, Any]] = []
    for cell in document["cells"]:
        runtime_id = str(uuid.uuid4())
        cell_uri = f"marimo-native-notebook-cell://release/{runtime_id}"
        code = cell["code"]
        cells.append({"cellId": runtime_id, "code": code})
        notebook_cells.append(
            {
                "kind": 2,
                "document": cell_uri,
                "metadata": {
                    "marimo": {
                        "name": cell.get("name") or "_",
                        "options": {
                            "column": cell.get("config", {}).get("column"),
                            "disabled": cell.get("config", {}).get("disabled", False),
                            "hide_code": cell.get("config", {}).get("hide_code", False),
                        },
                        "sourceProjections": {"markdown": None, "sql": None},
                    },
                    "marimoRuntime": {"stableId": runtime_id, "state": None},
                },
            }
        )
        text_documents.append(
            {
                "uri": cell_uri,
                "languageId": "python",
                "version": 1,
                "text": code,
            }
        )
    with tempfile.TemporaryDirectory(prefix="marimonative-release-runtime-") as directory:
        working_directory = Path(directory).resolve()
        notebook = working_directory / "release-smoke.py"
        notebook.write_text(source, encoding="utf-8")
        notebook_uri = notebook.as_uri()
        client.send(
            {
                "jsonrpc": "2.0",
                "method": "notebookDocument/didOpen",
                "params": {
                    "notebookDocument": {
                        "uri": notebook_uri,
                        "notebookType": "marimo-notebook",
                        "version": 1,
                        "cells": notebook_cells,
                        "metadata": {
                            "marimo": {
                                "appOptions": document.get("appOptions", {}),
                                "header": document.get("header"),
                                "notebookMetadata": document.get("metadata", {}),
                            }
                        },
                    },
                    "cellTextDocuments": text_documents,
                },
            }
        )
        client.send(
            {
                "jsonrpc": "2.0",
                "id": 4,
                "method": "marimo/command",
                "params": {
                    "kind": "execute",
                    "notebookUri": notebook_uri,
                    "executable": str(python),
                    "workingDirectory": str(working_directory),
                    "cells": cells,
                },
            }
        )
        notification_start = len(client.kernel_notifications)
        check_response(client.response(4, 30), 4)
        output_index, output_notification = client.kernel_notification(
            "cell-op",
            notebook_uri,
            30,
            after=notification_start,
            predicate=lambda item: item.get("output") is not None,
        )
        output = output_notification["notification"]["output"]
        if "42" not in json.dumps(output):
            raise RuntimeError(f"Sample notebook returned an unexpected output: {output}")
        client.kernel_notification(
            "completed-run", notebook_uri, 30, after=output_index + 1
        )
        relevant_notifications = [
            item["notification"]
            for item in client.kernel_notifications
            if item.get("notebookUri") == notebook_uri
        ]
        if any(item.get("op") == "kernel-startup-error" for item in relevant_notifications):
            raise RuntimeError(f"Kernel startup failed: {relevant_notifications}")

        client.send(
            {
                "jsonrpc": "2.0",
                "id": 5,
                "method": "marimo/command",
                "params": {"kind": "list-sessions"},
            }
        )
        sessions = check_response(client.response(5), 5)["sessions"]
        if len(sessions) != 1 or Path(sessions[0]["executable"]).resolve() != python:
            raise RuntimeError(f"Selected Python environment was not used: {sessions}")
        if sessions[0]["status"] != "idle":
            raise RuntimeError(f"Sample notebook did not finish execution: {sessions}")
        if descendants(process.pid) <= baseline_processes:
            raise RuntimeError("Sample notebook did not start a kernel process")

        client.send(
            {
                "jsonrpc": "2.0",
                "id": 6,
                "method": "marimo/command",
                "params": {"kind": "shutdown-all-sessions"},
            }
        )
        check_response(client.response(6), 6)
        client.send(
            {
                "jsonrpc": "2.0",
                "id": 7,
                "method": "marimo/command",
                "params": {"kind": "list-sessions"},
            }
        )
        remaining_sessions = check_response(client.response(7), 7)["sessions"]
        if remaining_sessions:
            raise RuntimeError(f"Sessions remained after shutdown: {remaining_sessions}")
        wait_for_descendants(process.pid, baseline_processes, 5)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("sidecar", type=Path)
    parser.add_argument("--deny-network", action="store_true")
    parser.add_argument("--runtime-acceptance", action="store_true")
    arguments = parser.parse_args()
    sidecar = arguments.sidecar.resolve()
    process = launch(sidecar, arguments.deny_network)
    client = LSPClient(process)
    forced_termination = False
    try:
        client.send({
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {"processId": os.getpid(), "clientInfo": {"name": "sidecar-smoke", "version": "1"}, "rootUri": None, "workspaceFolders": None, "capabilities": {}},
        })
        check_response(client.response(1), 1)
        client.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
        source = '''import marimo

__generated_with = "0.24.0"
app = marimo.App()

@app.cell
def _():
    import errno
    import socket
    probe = socket.socket()
    probe.settimeout(0.5)
    try:
        probe.connect(("1.1.1.1", 443))
    except OSError as error:
        external_network_blocked = error.errno in {errno.EPERM, errno.EACCES}
    else:
        external_network_blocked = False
    finally:
        probe.close()
    if not external_network_blocked:
        raise RuntimeError("external network access was not blocked")
    answer = 42
    answer
    return (answer,)

if __name__ == "__main__":
    app.run()
'''
        client.send({"jsonrpc": "2.0", "id": 2, "method": "marimo/command", "params": {"kind": "parse-notebook", "source": source}})
        parsed = check_response(client.response(2, 120), 2)
        if parsed.get("kind") != "success" or len(parsed["document"]["cells"]) != 1:
            raise RuntimeError(f"unexpected parse result: {parsed}")
        client.send({"jsonrpc": "2.0", "id": 3, "method": "marimo/command", "params": {"kind": "print-notebook", "document": parsed["document"]}})
        printed = check_response(client.response(3, 120), 3)
        if "marimo.App" not in printed["source"]:
            raise RuntimeError("print-notebook returned unexpected source")
        shutdown_request_id = 4
        if arguments.runtime_acceptance:
            runtime_acceptance(
                client, process, sidecar, parsed["document"], printed["source"]
            )
            shutdown_request_id = 8
        client.send(
            {
                "jsonrpc": "2.0",
                "id": shutdown_request_id,
                "method": "shutdown",
                "params": None,
            }
        )
        check_response(client.response(shutdown_request_id, 5), shutdown_request_id)
        client.send({"jsonrpc": "2.0", "method": "exit", "params": None})
        try:
            return_code = process.wait(timeout=5)
            if return_code != 0:
                raise RuntimeError(f"sidecar exited with {return_code}")
        except subprocess.TimeoutExpired:
            # The pinned pygls release can leave its stdio reader blocked after
            # acknowledging shutdown. Product shutdown is bounded at five
            # seconds, so exercise that same terminate fallback here.
            forced_termination = True
            terminate_process_group(process)
        else:
            wait_for_process_group_exit(process.pid, 2)
    except Exception:
        terminate_process_group(process)
        assert process.stderr is not None
        sys.stderr.write(process.stderr.read().decode(errors="replace"))
        raise
    print(
        "initialize/parse/print/shutdown passed; "
        f"network_denied={arguments.deny_network}; "
        f"runtime_acceptance={arguments.runtime_acceptance}; "
        f"forced_termination={forced_termination}"
    )


if __name__ == "__main__":
    main()
