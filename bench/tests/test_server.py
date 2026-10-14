import json
import re
import tempfile
import unittest
import urllib.error
import urllib.request
from pathlib import Path

import helpers  # noqa: F401
from server import BenchServer, PAGES_DIR

PAGES = ["index", "web-click", "web-form", "web-checkbox-select", "web-read", "web-scroll",
         "web-dialog", "web-wizard"]


def get(url):
    with urllib.request.urlopen(url, timeout=5) as r:
        return r.status, r.headers.get("Content-Type"), r.read().decode()


def post(url, data, raw=False):
    body = data if raw else json.dumps(data).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code


class ServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = BenchServer().start()
        cls.tmp = tempfile.TemporaryDirectory()
        cls.rec = Path(cls.tmp.name) / "r.jsonl"

    @classmethod
    def tearDownClass(cls):
        cls.srv.stop()
        cls.tmp.cleanup()

    def test_pages_served_and_self_contained(self):
        for p in PAGES:
            status, ctype, body = get(f"{self.srv.base_url}/{p}.html")
            self.assertEqual(status, 200, p)
            self.assertIn("text/html", ctype)
            self.assertNotRegex(body, r'(src|href)=["\']https?://', p)   # no external resources
        status, ctype, _ = get(self.srv.base_url + "/_common.js")
        self.assertEqual(status, 200)

    def test_pages_use_real_controls(self):
        form = (PAGES_DIR / "web-form.html").read_text()
        for needle in ('<label for="name">', '<label for="email">', "<button type=\"submit\">Submit"):
            self.assertIn(needle, form)
        self.assertIn("<select", (PAGES_DIR / "web-checkbox-select.html").read_text())
        for p in PAGES_DIR.glob("*.html"):
            self.assertNotRegex(p.read_text(), r"<div[^>]*onclick", p.name)

    def test_traversal_and_missing(self):
        for path in ("/../server.py", "/nope.html", "/..%2fserver.py", "/pages/../server.py"):
            with self.assertRaises(urllib.error.HTTPError) as cm:
                get(self.srv.base_url + path)
            self.assertEqual(cm.exception.code, 404, path)

    def test_record_lifecycle(self):
        url = self.srv.base_url + "/record"
        self.srv.set_record_path(None)
        self.assertEqual(post(url, {"page": "x"}), 409)
        self.srv.set_record_path(self.rec)
        self.assertEqual(post(url, {"page": "web-click", "event": "click", "target": "Delta"}), 204)
        self.assertEqual(post(url, b"not json", raw=True), 400)
        self.assertEqual(post(url, b"[1,2]", raw=True), 400)
        recs = self.srv.records()
        self.assertEqual(len(recs), 1)
        self.assertEqual(recs[0]["target"], "Delta")
        self.assertIn("received_at", recs[0])
        self.assertEqual(len(self.rec.read_text().splitlines()), 1)
        self.srv.set_record_path(self.rec)       # new run truncates
        self.assertEqual(self.srv.records(), [])


if __name__ == "__main__":
    unittest.main()
