"""Minimal MCP stdio client (NDJSON JSON-RPC 2.0), standard library only.

Used by the Ollama tool loop and by the TextEdit/Calculator checkers.
A reader thread routes responses to waiting callers, so a slow tool call
never loses a message and a dead server fails the caller fast.
"""
from __future__ import annotations

import json
import os
import queue
import signal
import subprocess
import threading
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Sequence

PROTOCOL_VERSION = "2025-06-18"


class MCPError(Exception):
    pass


@dataclass
class ToolResult:
    text: str
    is_error: bool
    content: List[Dict[str, Any]] = field(default_factory=list)
    elapsed: float = 0.0


_EOF = object()


class MCPClient:
    def __init__(self, command: Sequence[str], env: Optional[Dict[str, str]] = None,
                 cwd: Optional[str] = None, stderr_path: Optional[str] = None):
        self.command = list(command)
        self.env = dict(env) if env is not None else dict(os.environ)
        self.cwd = cwd
        self.stderr_path = stderr_path
        self.proc: Optional[subprocess.Popen] = None
        self.server_info: Dict[str, Any] = {}
        self.instructions: str = ""
        self._next_id = 0
        self._lock = threading.Lock()
        self._write_lock = threading.Lock()
        self._pending: Dict[int, "queue.Queue[Any]"] = {}
        self._reader: Optional[threading.Thread] = None
        self._stderr_fh = None

    # -- lifecycle ---------------------------------------------------------
    def start(self) -> "MCPClient":
        self._stderr_fh = open(self.stderr_path, "ab") if self.stderr_path else subprocess.DEVNULL
        # Own process group so close() can reap the whole tree.
        self.proc = subprocess.Popen(
            self.command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=self._stderr_fh, env=self.env, cwd=self.cwd, start_new_session=True)
        self._reader = threading.Thread(target=self._read_loop, daemon=True)
        self._reader.start()
        return self

    def initialize(self, timeout: float = 30.0) -> Dict[str, Any]:
        result = self.request("initialize", {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {},
            "clientInfo": {"name": "bench-harness", "version": "1"},
        }, timeout=timeout)
        self.server_info = result.get("serverInfo", {}) or {}
        self.instructions = result.get("instructions", "") or ""
        self.notify("notifications/initialized")
        return result

    def close(self) -> None:
        proc = self.proc
        if proc is None:
            return
        try:
            if proc.stdin:
                proc.stdin.close()
        except Exception:
            pass
        try:
            proc.wait(timeout=2)
        except Exception:
            pass
        for sig in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.killpg(proc.pid, sig)
            except (ProcessLookupError, PermissionError):
                break
            try:
                proc.wait(timeout=2)
                break
            except Exception:
                continue
        if self._reader is not None:
            self._reader.join(timeout=2)
        try:
            if proc.stdout and not (self._reader and self._reader.is_alive()):
                proc.stdout.close()
        except Exception:
            pass
        if self._stderr_fh not in (None, subprocess.DEVNULL):
            try:
                self._stderr_fh.close()
            except Exception:
                pass
        self.proc = None

    def __enter__(self) -> "MCPClient":
        self.start()
        self.initialize()
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    # -- wire --------------------------------------------------------------
    def _send(self, obj: Dict[str, Any]) -> None:
        if not self.proc or not self.proc.stdin:
            raise MCPError("server not running")
        data = (json.dumps(obj) + "\n").encode()
        with self._write_lock:
            try:
                self.proc.stdin.write(data)
                self.proc.stdin.flush()
            except (BrokenPipeError, ValueError, OSError) as e:
                raise MCPError(f"write failed: {e}")

    def _read_loop(self) -> None:
        assert self.proc and self.proc.stdout
        for raw in iter(self.proc.stdout.readline, b""):
            line = raw.strip()
            if not line.startswith(b"{"):
                continue  # tolerate stray log lines on stdout
            try:
                msg = json.loads(line)
            except ValueError:
                continue
            if "method" in msg and "id" in msg:  # server -> client request
                reply: Dict[str, Any] = {"jsonrpc": "2.0", "id": msg["id"]}
                if msg["method"] == "ping":
                    reply["result"] = {}
                else:
                    reply["error"] = {"code": -32601, "message": "method not found"}
                try:
                    self._send(reply)
                except MCPError:
                    pass
            elif "id" in msg:
                with self._lock:
                    q = self._pending.get(msg["id"])
                if q is not None:
                    q.put(msg)
        with self._lock:
            waiting = list(self._pending.values())
        for q in waiting:
            q.put(_EOF)

    def notify(self, method: str, params: Optional[Dict[str, Any]] = None) -> None:
        obj: Dict[str, Any] = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            obj["params"] = params
        self._send(obj)

    def request(self, method: str, params: Optional[Dict[str, Any]] = None,
                timeout: float = 60.0) -> Dict[str, Any]:
        with self._lock:
            self._next_id += 1
            rid = self._next_id
            q: "queue.Queue[Any]" = queue.Queue()
            self._pending[rid] = q
        try:
            obj: Dict[str, Any] = {"jsonrpc": "2.0", "id": rid, "method": method}
            if params is not None:
                obj["params"] = params
            self._send(obj)
            try:
                msg = q.get(timeout=max(0.05, timeout))
            except queue.Empty:
                raise MCPError(f"timeout after {timeout:.0f}s waiting for {method}")
            if msg is _EOF:
                raise MCPError("server closed the connection")
            if "error" in msg:
                raise MCPError(f"{method}: {json.dumps(msg['error'])[:500]}")
            return msg.get("result", {}) or {}
        finally:
            with self._lock:
                self._pending.pop(rid, None)

    # -- MCP operations ----------------------------------------------------
    def list_tools(self, timeout: float = 30.0) -> List[Dict[str, Any]]:
        tools: List[Dict[str, Any]] = []
        cursor = None
        while True:
            res = self.request("tools/list", {"cursor": cursor} if cursor else {}, timeout=timeout)
            tools.extend(res.get("tools", []))
            cursor = res.get("nextCursor")
            if not cursor:
                return tools

    def call_tool(self, name: str, arguments: Optional[Dict[str, Any]] = None,
                  timeout: float = 60.0) -> ToolResult:
        t0 = time.monotonic()
        res = self.request("tools/call", {"name": name, "arguments": arguments or {}}, timeout=timeout)
        parts: List[str] = []
        for c in res.get("content", []) or []:
            if c.get("type") == "text":
                parts.append(c.get("text", ""))
            elif c.get("type") == "image":
                parts.append(f"[image {c.get('mimeType', '')} omitted]")
            else:
                parts.append(f"[{c.get('type')} content omitted]")
        return ToolResult(text="\n".join(parts), is_error=bool(res.get("isError")),
                          content=res.get("content", []) or [], elapsed=time.monotonic() - t0)
