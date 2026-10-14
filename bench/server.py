"""Tiny page server + action recorder (standard library only).

GET  /<page>.html   serves static task pages from bench/pages/
POST /record        JSON object; appended as one line to the active run's JSONL file
GET  /health        liveness probe

Success of every web task is decided from the JSONL file, never from what an
agent says. Binds to 127.0.0.1 only.
"""
from __future__ import annotations

import argparse
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, List, Optional

PAGES_DIR = Path(__file__).resolve().parent / "pages"
MIME = {".html": "text/html; charset=utf-8", ".js": "application/javascript; charset=utf-8",
        ".css": "text/css; charset=utf-8"}
MAX_BODY = 64 * 1024


def read_records(path: Optional[Path]) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    if not path or not Path(path).exists():
        return out
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            if isinstance(obj, dict):
                out.append(obj)
    return out


class BenchServer:
    def __init__(self, pages_dir: Path = PAGES_DIR, host: str = "127.0.0.1", port: int = 0):
        self.pages_dir = Path(pages_dir)
        self._record_path: Optional[Path] = None
        self._lock = threading.Lock()
        outer = self

        class Handler(BaseHTTPRequestHandler):
            server_version = "BenchPages/1"

            def log_message(self, *a):  # keep the console quiet
                pass

            def _send(self, code: int, body: bytes = b"", ctype: str = "text/plain; charset=utf-8"):
                self.send_response(code)
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(body)

            def do_HEAD(self):
                self.do_GET()

            def do_GET(self):
                path = self.path.split("?", 1)[0].split("#", 1)[0]
                if path == "/health":
                    return self._send(200, b'{"ok":true}', "application/json")
                if path == "/":
                    path = "/index.html"
                name = path.lstrip("/")
                if not name or "/" in name or "\\" in name or name.startswith(".") or \
                        Path(name).suffix not in MIME:
                    return self._send(404, b"not found")
                f = outer.pages_dir / name
                if not f.is_file():
                    return self._send(404, b"not found")
                self._send(200, f.read_bytes(), MIME[Path(name).suffix])

            def do_POST(self):
                if self.path.split("?", 1)[0] != "/record":
                    return self._send(404, b"not found")
                try:
                    n = int(self.headers.get("Content-Length", "0"))
                except ValueError:
                    return self._send(400, b"bad length")
                if n <= 0 or n > MAX_BODY:
                    return self._send(400, b"bad length")
                try:
                    obj = json.loads(self.rfile.read(n).decode("utf-8"))
                except ValueError:
                    return self._send(400, b"bad json")
                if not isinstance(obj, dict):
                    return self._send(400, b"object expected")
                if not outer.append(obj):
                    return self._send(409, b"no active run")
                self._send(204)

        self.httpd = ThreadingHTTPServer((host, port), Handler)
        self.httpd.daemon_threads = True
        self._thread: Optional[threading.Thread] = None

    @property
    def port(self) -> int:
        return self.httpd.server_address[1]

    @property
    def base_url(self) -> str:
        return f"http://127.0.0.1:{self.port}"

    def set_record_path(self, path: Optional[Path]) -> None:
        with self._lock:
            self._record_path = Path(path) if path else None
            if self._record_path:
                self._record_path.parent.mkdir(parents=True, exist_ok=True)
                self._record_path.write_text("")  # fresh file per run

    def append(self, obj: Dict[str, Any]) -> bool:
        with self._lock:
            if not self._record_path:
                return False
            rec = dict(obj)
            rec["received_at"] = round(time.time(), 3)
            with open(self._record_path, "a", encoding="utf-8") as fh:
                fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
            return True

    def records(self) -> List[Dict[str, Any]]:
        with self._lock:
            return read_records(self._record_path)

    def start(self) -> "BenchServer":
        self._thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self._thread.start()
        return self

    def stop(self) -> None:
        self.httpd.shutdown()
        self.httpd.server_close()


def main() -> None:
    ap = argparse.ArgumentParser(description="Serve bench pages and record actions.")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--record", type=Path, default=Path("record.jsonl"))
    args = ap.parse_args()
    srv = BenchServer(port=args.port)
    srv.set_record_path(args.record)
    print(f"serving {srv.base_url}/  recording to {args.record}")
    try:
        srv.httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
