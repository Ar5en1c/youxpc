"""Fake agent for --dry-run. Never touches the desktop: it POSTs the records a
correct (or, for chosen tasks, a wrong) agent would have produced to the local
recorder, and sets text on FakeDesktop. All numeric metrics are null."""
from __future__ import annotations

import json
import urllib.request
from typing import Dict, List, Set

from .base import AgentContext, AgentResult, System


def _post(base_url: str, obj: Dict) -> None:
    req = urllib.request.Request(base_url + "/record", data=json.dumps(obj).encode(),
                                 headers={"Content-Type": "application/json"})
    urllib.request.urlopen(req, timeout=5).read()


class FakeSystem(System):
    description = "dry-run stand-in"

    def __init__(self, name, opts, fail_tasks: Set[str] = frozenset()):
        super().__init__(name, opts)
        self.fail_tasks = set(fail_tasks)

    @classmethod
    def matches(cls, name): return True

    def run(self, ctx: AgentContext) -> AgentResult:
        t = ctx.task.id
        good = t not in self.fail_tasks
        u = ctx.base_url
        ans = "Done."
        if t == "calc-multiply": ans = "47 × 19 = 893" if good else "47 × 19 = 883"
        elif t == "calc-chain": ans = "The result is 96." if good else "The result is 69."
        elif t == "textedit-type":
            ctx.desktop.texts["TextEdit"] = "quartz-4821" if good else "quartz-482"
        elif t == "web-click":
            _post(u, {"page": t, "event": "click", "target": "Delta" if good else "Echo"})
        elif t == "web-form":
            _post(u, {"page": t, "event": "submit", "name": "quartz-4821",
                      "email": "zx@example.test" if good else ""})
        elif t == "web-checkbox-select":
            _post(u, {"page": t, "event": "save", "express": True, "colour": "Blue" if good else "Red"})
        elif t == "web-read": ans = "The access code is 7391." if good else "The access code is 5064."
        elif t == "web-scroll":
            if good: _post(u, {"page": t, "event": "click", "target": "Confirm order"})
        elif t == "web-dialog":
            _post(u, {"page": t, "event": "dialog_open"})
            _post(u, {"page": t, "event": "rename", "value": "basalt-77" if good else "basalt"})
        elif t == "web-wizard":
            vals = ["cedar-305", "harbor-218", "ember-946"]
            for i, v in enumerate(vals[:2], 1):
                _post(u, {"page": t, "event": "step", "step": i, "value": v})
            if good: _post(u, {"page": t, "event": "finish", "values": vals})
        if t.startswith("calc"):
            ctx.desktop.texts["Calculator"] = ans.split("=")[-1].strip() if good else ""
        return AgentResult(final_answer=ans, extra={"dry_run": True})
