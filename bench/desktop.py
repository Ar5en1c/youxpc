"""Everything that touches the real desktop lives here, behind one interface.

MacDesktop launches/terminates apps and reads app text through the YouxPC MCP
server. FakeDesktop does none of that, so `run.py --dry-run` and the unit tests
never touch the screen. MacDesktop refuses to act unless constructed with
confirmed=True (run.py passes that only when --yes is given).
"""
from __future__ import annotations

import os
import re
import shutil
import signal
import subprocess
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional

from mcp_client import MCPClient, MCPError

BRAVE_APP = "Brave Browser"
PROFILE_PREFIX = "youxpc-bench-brave-"


class SetupError(Exception):
    """The environment could not be prepared (infrastructure, not agent failure)."""


@dataclass
class Handle:
    kind: str                       # "app" | "browser"
    app_name: str = ""
    pids: List[int] = field(default_factory=list)   # pids this harness started
    profile_dir: Optional[str] = None
    note: str = ""


def pids_with_arg(ps_output: str, token: str, exclude: Optional[int] = None) -> List[int]:
    """Parse `ps -axo pid=,command=` output; return pids whose command line
    contains `token` as a whole argument (followed by whitespace or end)."""
    pat = re.compile(re.escape(token) + r"(\s|$)")
    out = []
    for line in ps_output.splitlines():
        line = line.strip()
        if not line:
            continue
        pid_s, _, cmd = line.partition(" ")
        if not pid_s.isdigit():
            continue
        pid = int(pid_s)
        if pid == exclude or pid == os.getpid():
            continue
        if pat.search(cmd):
            out.append(pid)
    return out


class Desktop:
    def launch_app(self, app_name: str, path: Optional[str] = None) -> Handle: raise NotImplementedError
    def launch_browser(self, url: str) -> Handle: raise NotImplementedError
    def terminate(self, handle: Optional[Handle]) -> None: raise NotImplementedError
    def read_app_text(self, app_name: str, bundle_id: str) -> str: raise NotImplementedError


class FakeDesktop(Desktop):
    """No processes, no GUI. Keeps a log of what would have happened."""

    def __init__(self) -> None:
        self.log: List[str] = []
        self.texts: Dict[str, str] = {}

    def launch_app(self, app_name, path=None):
        self.log.append(f"launch_app {app_name} {path or ''}".strip())
        self.texts.setdefault(app_name, "")
        return Handle("app", app_name=app_name)

    def launch_browser(self, url):
        """Pretend to open the URL: fetch the page from the local server and report
        the load event the real page would send (localhost HTTP only)."""
        import json as _json
        import urllib.request
        self.log.append(f"launch_browser {url}")
        urllib.request.urlopen(url, timeout=5).read()
        base, _, name = url.rpartition("/")
        body = _json.dumps({"page": name.rsplit(".", 1)[0], "event": "load"}).encode()
        urllib.request.urlopen(urllib.request.Request(
            base + "/record", data=body, headers={"Content-Type": "application/json"}), timeout=5).read()
        return Handle("browser", app_name=BRAVE_APP, profile_dir="(fake)")

    def terminate(self, handle):
        if handle is not None:
            self.log.append(f"terminate {handle.kind} {handle.app_name}")

    def read_app_text(self, app_name, bundle_id):
        self.log.append(f"read_app_text {app_name}")
        return self.texts.get(app_name, "")


class MacDesktop(Desktop):
    def __init__(self, youxpc_bin: str, confirmed: bool = False,
                 allow_preexisting: bool = False):
        if not confirmed:
            raise RuntimeError("MacDesktop touches the real desktop; pass confirmed=True")
        self.youxpc_bin = youxpc_bin
        self.allow_preexisting = allow_preexisting

    # -- helpers -----------------------------------------------------------
    @staticmethod
    def _pgrep_exact(name: str) -> List[int]:
        r = subprocess.run(["pgrep", "-x", name], capture_output=True, text=True)
        return [int(x) for x in r.stdout.split() if x.isdigit()]

    @staticmethod
    def _ps() -> str:
        return subprocess.run(["ps", "-axo", "pid=,command="], capture_output=True, text=True).stdout

    @staticmethod
    def _alive(pid: int) -> bool:
        try:
            os.kill(pid, 0)
            return True
        except ProcessLookupError:
            return False
        except PermissionError:
            return True

    def _stop_pids(self, pids: List[int]) -> None:
        for sig, wait in ((signal.SIGTERM, 4.0), (signal.SIGKILL, 2.0)):
            live = [p for p in pids if self._alive(p)]
            if not live:
                return
            for p in live:
                try:
                    os.kill(p, sig)
                except (ProcessLookupError, PermissionError):
                    pass
            end = time.time() + wait
            while time.time() < end and any(self._alive(p) for p in live):
                time.sleep(0.2)

    # -- interface ---------------------------------------------------------
    def launch_app(self, app_name, path=None):
        before = set(self._pgrep_exact(app_name))
        if before and not self.allow_preexisting:
            raise SetupError(f"{app_name} is already running (pids {sorted(before)}); refusing to "
                             f"drive or quit an app the harness did not start "
                             f"(pass --allow-preexisting-apps to override)")
        cmd = ["open", "-a", app_name]
        if path:
            cmd.append(path)
        cmd += ["--args", "-ApplePersistenceIgnoreState", "YES"]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            raise SetupError(f"open failed: {r.stderr.strip()}")
        end = time.time() + 20
        new: List[int] = []
        while time.time() < end:
            new = sorted(set(self._pgrep_exact(app_name)) - before)
            if new:
                break
            time.sleep(0.3)
        if not new and not before:
            raise SetupError(f"{app_name} did not start")
        time.sleep(1.5)  # let the first window appear
        return Handle("app", app_name=app_name, pids=new,
                      note="pre-existing instance left running" if before else "")

    def launch_browser(self, url):
        profile = tempfile.mkdtemp(prefix=PROFILE_PREFIX)
        cmd = ["open", "-na", BRAVE_APP, "--args", f"--user-data-dir={profile}",
               "--no-first-run", "--no-default-browser-check", "--new-window", url]
        r = subprocess.run(cmd, capture_output=True, text=True)
        h = Handle("browser", app_name=BRAVE_APP, profile_dir=profile)
        if r.returncode != 0:
            self.terminate(h)
            raise SetupError(f"open Brave failed: {r.stderr.strip()}")
        end = time.time() + 20
        while time.time() < end:
            h.pids = pids_with_arg(self._ps(), f"--user-data-dir={profile}")
            if h.pids:
                return h
            time.sleep(0.3)
        self.terminate(h)
        raise SetupError("Brave instance did not appear")

    def terminate(self, handle):
        if handle is None:
            return
        if handle.kind == "browser" and handle.profile_dir:
            token = f"--user-data-dir={handle.profile_dir}"
            for _ in range(3):  # helpers can respawn briefly
                pids = pids_with_arg(self._ps(), token)
                if not pids:
                    break
                self._stop_pids(pids)
            p = Path(handle.profile_dir)
            if p.name.startswith(PROFILE_PREFIX) and \
                    os.path.realpath(str(p.parent)) == os.path.realpath(tempfile.gettempdir()):
                for _ in range(5):
                    shutil.rmtree(p, ignore_errors=True)
                    if not p.exists():
                        break
                    time.sleep(0.5)
        else:
            self._stop_pids(handle.pids)  # only pids the harness started

    def read_app_text(self, app_name, bundle_id):
        env = dict(os.environ)
        env["YOUXPC_ALLOW_APPS"] = bundle_id
        text = ""
        try:
            with MCPClient([self.youxpc_bin, "mcp"], env=env) as c:
                r = c.call_tool("pc_read", {"app": app_name}, timeout=30)
                text = r.text
                if not text.strip() or r.is_error:
                    r2 = c.call_tool("pc_snapshot", {"app": app_name, "full": True}, timeout=30)
                    text = text + "\n" + r2.text
        except MCPError as e:
            raise SetupError(f"checker could not read {app_name}: {e}")
        return text
