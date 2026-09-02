#!/usr/bin/env python3
"""Exercise the bundled LSP sidecar over stdio, optionally without network."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import time
from typing import Any


class LSPClient:
    def __init__(self, process: subprocess.Popen[bytes]) -> None:
        self.process = process

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
        command = ["/usr/bin/sandbox-exec", "-p", "(version 1)(allow default)(deny network*)", *command]
    environment = {
        "HOME": os.environ.get("HOME", "/tmp"),
        "LANG": "en_US.UTF-8",
        "PATH": "/usr/bin:/bin",
        "PYTHONNOUSERSITE": "1",
        "PYTHONUTF8": "1",
        "TMPDIR": os.environ.get("TMPDIR", "/tmp"),
    }
    return subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment)


def check_response(response: dict[str, Any], request_id: int) -> Any:
    if "error" in response:
        raise RuntimeError(f"request {request_id} failed: {response['error']}")
    return response["result"]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("sidecar", type=Path)
    parser.add_argument("--deny-network", action="store_true")
    arguments = parser.parse_args()
    process = launch(arguments.sidecar.resolve(), arguments.deny_network)
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
    value = 42
    return (value,)

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
        client.send({"jsonrpc": "2.0", "id": 4, "method": "shutdown", "params": None})
        check_response(client.response(4, 5), 4)
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
            process.terminate()
            process.wait(timeout=2)
    except Exception:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
        assert process.stderr is not None
        sys.stderr.write(process.stderr.read().decode(errors="replace"))
        raise
    print(
        "initialize/parse/print/shutdown passed; "
        f"network_denied={arguments.deny_network}; "
        f"forced_termination={forced_termination}"
    )


if __name__ == "__main__":
    main()
