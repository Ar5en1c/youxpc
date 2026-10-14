"""Run a child process under a hard timeout and kill its whole process tree."""
from __future__ import annotations

import os
import signal
import subprocess
import time
from dataclasses import dataclass
from typing import Dict, Optional, Sequence


@dataclass
class RunInfo:
    returncode: Optional[int]
    timed_out: bool
    elapsed: float
    spawn_error: Optional[str] = None


def kill_group(pid: int, grace: float = 2.0) -> None:
    """SIGTERM then SIGKILL the process group led by pid."""
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(pid, sig)
        except (ProcessLookupError, PermissionError):
            return
        if sig == signal.SIGTERM:
            time.sleep(grace)


def run_with_timeout(cmd: Sequence[str], *, timeout: float, env: Optional[Dict[str, str]] = None,
                     cwd: Optional[str] = None, stdin_text: Optional[str] = None,
                     stdout_path: str, stderr_path: str) -> RunInfo:
    """Run cmd in its own session. stdout/stderr go to files so partial output
    survives a kill. After exit (normal or not) any stragglers in the group are
    killed too (for example an MCP server the agent CLI spawned)."""
    t0 = time.monotonic()
    with open(stdout_path, "wb") as out, open(stderr_path, "wb") as err:
        try:
            proc = subprocess.Popen(
                list(cmd), stdin=subprocess.PIPE if stdin_text is not None else subprocess.DEVNULL,
                stdout=out, stderr=err, env=env, cwd=cwd, start_new_session=True)
        except OSError as e:
            return RunInfo(None, False, 0.0, spawn_error=str(e))
        timed_out = False
        try:
            proc.communicate(input=stdin_text.encode() if stdin_text is not None else None,
                             timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            kill_group(proc.pid)
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
        finally:
            if proc.poll() is None:
                kill_group(proc.pid, grace=0.5)
            else:
                _reap_group(proc.pid)
        return RunInfo(proc.returncode, timed_out, time.monotonic() - t0)


def _reap_group(pid: int) -> None:
    """Kill leftover members of the group after the leader exited normally."""
    try:
        os.killpg(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass
