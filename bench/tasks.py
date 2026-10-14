"""The benchmark tasks (ten short ones and a harder seven): prompt, setup, checker, teardown, allowed apps, limit.

Every string an agent must type is an inert token. Web tasks are judged from
the recorder's JSONL, calculator tasks from the final answer (plus a separately
recorded desktop-evidence read), TextEdit from the document text read through
the YouxPC MCP server.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

from desktop import Desktop, Handle, SetupError

BUNDLE = {"Calculator": "com.apple.calculator", "TextEdit": "com.apple.TextEdit",
          "Brave Browser": "com.brave.Browser"}

PROMPT_TAIL = ("Use the {app} app, which is already open. "
               "When you are done, reply with a short final message.")


@dataclass
class TaskContext:
    base_url: str
    records: Callable[[], List[Dict[str, Any]]]
    desktop: Desktop
    scratch: Path
    dry_run: bool = False


@dataclass
class CheckResult:
    success: bool
    note: str = ""
    evidence: Optional[bool] = None   # secondary desktop-side evidence, where available


@dataclass(frozen=True)
class Task:
    id: str
    sentence: str
    app_name: str
    kind: str                          # calc | textedit | web
    time_limit: int
    page: Optional[str] = None
    expect: Optional[str] = None       # expected number/token for answer-based tasks
    check_fn: Callable[["Task", TaskContext, str], CheckResult] = None  # type: ignore

    @property
    def bundle_ids(self) -> Tuple[str, ...]:
        return (BUNDLE[self.app_name],)

    def prompt(self) -> str:
        return f"{self.sentence} {PROMPT_TAIL.format(app=self.app_name)}"

    # -- lifecycle ---------------------------------------------------------
    def setup(self, ctx: TaskContext) -> Optional[Handle]:
        if self.kind == "calc":
            return ctx.desktop.launch_app("Calculator")
        if self.kind == "textedit":
            f = ctx.scratch / "bench-note.txt"
            f.write_text("")
            return ctx.desktop.launch_app("TextEdit", str(f))
        h = ctx.desktop.launch_browser(f"{ctx.base_url}/{self.page}.html")
        _wait_for(ctx, lambda recs: any(r.get("page") == self.page and r.get("event") == "load"
                                        for r in recs), 25,
                  f"page {self.page} never reported 'load' (browser did not open it)", h)
        return h

    def teardown(self, ctx: TaskContext, handle: Optional[Handle]) -> None:
        ctx.desktop.terminate(handle)

    def check(self, ctx: TaskContext, answer: str) -> CheckResult:
        return self.check_fn(self, ctx, answer or "")


def _wait_for(ctx: TaskContext, pred, timeout: float, msg: str, handle: Optional[Handle]) -> None:
    import time
    end = time.time() + timeout
    while time.time() < end:
        if pred(ctx.records()):
            return
        time.sleep(0.25)
    ctx.desktop.terminate(handle)
    raise SetupError(msg)


# -- checkers ----------------------------------------------------------------
def contains_number(text: str, number: str) -> bool:
    """True if `number` appears as a standalone number (not inside a longer one)."""
    return re.search(rf"(?<![\d.,]){re.escape(number)}(?![\d]|[.,]\d)", text) is not None


def _check_calc(task: Task, ctx: TaskContext, answer: str) -> CheckResult:
    ok = contains_number(answer, task.expect or "")
    ev: Optional[bool] = None
    try:
        shown = ctx.desktop.read_app_text("Calculator", BUNDLE["Calculator"])
        ev = contains_number(shown, task.expect or "")
    except Exception as e:  # evidence is best-effort and never changes success
        return CheckResult(ok, f"answer {'has' if ok else 'lacks'} {task.expect}; evidence read failed: {e}")
    return CheckResult(ok, f"answer {'has' if ok else 'lacks'} {task.expect}; "
                           f"Calculator display {'shows' if ev else 'does not show'} it", ev)


TOKEN = "quartz-4821"


def _check_textedit(task: Task, ctx: TaskContext, answer: str) -> CheckResult:
    text = ctx.desktop.read_app_text("TextEdit", BUNDLE["TextEdit"])
    n = text.count(TOKEN)
    return CheckResult(n >= 1, f"token occurs {n}x in TextEdit text", n >= 1)


def _events(ctx: TaskContext, page: str, event: str) -> List[Dict[str, Any]]:
    return [r for r in ctx.records() if r.get("page") == page and r.get("event") == event]


def _check_click(task, ctx, answer):
    ev = _events(ctx, "web-click", "click")
    targets = [e.get("target") for e in ev]
    return CheckResult(targets == ["Delta"], f"clicks recorded: {targets}")


def _check_form(task, ctx, answer):
    ev = _events(ctx, "web-form", "submit")
    if not ev:
        return CheckResult(False, "no submission recorded")
    last = ev[-1]
    ok = last.get("name") == TOKEN and last.get("email") == "zx@example.test"
    return CheckResult(ok, f"{len(ev)} submission(s); last name={last.get('name')!r} email={last.get('email')!r}")


def _check_checkbox(task, ctx, answer):
    ev = _events(ctx, "web-checkbox-select", "save")
    if not ev:
        return CheckResult(False, "no save recorded")
    last = ev[-1]
    ok = last.get("express") is True and last.get("colour") == "Blue"
    return CheckResult(ok, f"last save express={last.get('express')!r} colour={last.get('colour')!r}")


def _check_read(task, ctx, answer):
    ok = contains_number(answer, "7391")
    return CheckResult(ok, f"answer {'has' if ok else 'lacks'} 7391")


def _check_scroll(task, ctx, answer):
    ev = _events(ctx, "web-scroll", "click")
    ok = any(e.get("target") == "Confirm order" for e in ev)
    return CheckResult(ok, f"{len(ev)} click(s) recorded")


def _check_dialog(task, ctx, answer):
    ev = _events(ctx, "web-dialog", "rename")
    if not ev:
        return CheckResult(False, "no rename recorded")
    return CheckResult(ev[-1].get("value") == "basalt-77", f"last rename value={ev[-1].get('value')!r}")


WIZARD_VALUES = ["cedar-305", "harbor-218", "ember-946"]


def _check_wizard(task, ctx, answer):
    ev = _events(ctx, "web-wizard", "finish")
    if not ev:
        return CheckResult(False, "wizard not finished")
    vals = ev[-1].get("values")
    return CheckResult(vals == WIZARD_VALUES, f"finished with values={vals!r}")


def _web(id_, sentence, check, limit=150):
    return Task(id_, sentence, "Brave Browser", "web", limit, page=id_, check_fn=check)


TASKS: List[Task] = [
    Task("calc-multiply", "Calculate 47 × 19 in Calculator and tell me the result.",
         "Calculator", "calc", 120, expect="893", check_fn=_check_calc),
    Task("calc-chain", "Calculate (128 + 256) ÷ 4 in Calculator and tell me the result.",
         "Calculator", "calc", 120, expect="96", check_fn=_check_calc),
    Task("textedit-type", f"Type the text {TOKEN} into the open TextEdit document.",
         "TextEdit", "textedit", 120, check_fn=_check_textedit),
    _web("web-click", "On the open web page, click the button labelled Delta.", _check_click),
    _web("web-form", f"Fill in the Name field with {TOKEN} and the Email field with zx@example.test, "
                     "then press Submit.", _check_form),
    _web("web-checkbox-select", "Tick the 'Express shipping' checkbox, choose 'Blue' in the colour "
                                "dropdown, then press Save.", _check_checkbox),
    _web("web-read", "Find the access code shown on the open page and tell me what it is.", _check_read),
    _web("web-scroll", "Scroll down the open page and click the 'Confirm order' button.", _check_scroll),
    _web("web-dialog", "Click 'Rename', enter basalt-77 in the dialog's text field, and confirm with OK.",
         _check_dialog),
    _web("web-wizard", "Complete the three-step form: enter cedar-305 in step 1, harbor-218 in step 2 "
                       "and ember-946 in step 3, pressing Next after steps 1 and 2 and Finish at the end.",
         _check_wizard, limit=240),
]


# -- harder set ---------------------------------------------------------------
# The ten tasks above are short, and a capable model passes nearly all of them
# with any tool. These seven are where tools can come apart: buttons that share
# a name, state that has to be read before it is changed, content that arrives
# late, and longer sequences.
def _check_rows(task, ctx, answer):
    got = [(e.get("who"), e.get("decision")) for e in _events(ctx, "web-rows", "decide")]
    want = {("Marlow Quist", "Approve"), ("Tessa Bright", "Reject")}
    return CheckResult(set(got) == want and len(got) == 2, f"decisions recorded: {got}")


LONG_FORM = {"name": "Rowan Tiller", "email": "rt@example.test", "role": "Editor", "team": "Platform",
             "summary": True, "usage": False, "notes": "amber-5512"}


def _check_long_form(task, ctx, answer):
    ev = _events(ctx, "web-long-form", "register")
    if not ev:
        return CheckResult(False, "no registration recorded")
    wrong = {k: ev[-1].get(k) for k, v in LONG_FORM.items() if ev[-1].get(k) != v}
    return CheckResult(not wrong, "all seven fields correct" if not wrong else f"wrong fields: {wrong}")


def _check_confirm_delete(task, ctx, answer):
    deleted = [e.get("name") for e in _events(ctx, "web-confirm-delete", "delete")]
    return CheckResult(deleted == ["draft-b7"], f"deleted: {deleted}")


def _check_tabs(task, ctx, answer):
    ev = [e for e in _events(ctx, "web-tabs", "save") if e.get("section") == "billing"]
    if not ev:
        return CheckResult(False, "billing settings never saved")
    last = ev[-1]
    ok = last.get("plan") == "Team" and str(last.get("seats")).strip() == "12"
    return CheckResult(ok, f"saved plan={last.get('plan')!r} seats={last.get('seats')!r}")


def _check_async_search(task, ctx, answer):
    opened = [e.get("target") for e in _events(ctx, "web-async-search", "open")]
    return CheckResult(opened == ["Osprey ridge trail"], f"opened: {opened}")


def _check_reveal(task, ctx, answer):
    ev = _events(ctx, "web-reveal-enter", "pair")
    if not ev:
        return CheckResult(False, "no pairing attempt recorded")
    return CheckResult(ev[-1].get("value") == "58-2046-KM", f"{len(ev)} attempt(s); last value={ev[-1].get('value')!r}")


HARD_TASKS: List[Task] = [
    _web("web-rows", "On the open page, approve the request from Marlow Quist and reject the request from "
                     "Tessa Bright. Leave the other requests alone.", _check_rows, limit=180),
    _web("web-long-form", "Fill in the registration form: full name Rowan Tiller, email rt@example.test, role Editor, "
                          "team Platform, weekly summary on, share usage data off, notes amber-5512. Then press Register.",
         _check_long_form, limit=240),
    _web("web-confirm-delete", "Delete the draft named draft-b7 and confirm the deletion. Do not delete anything else.",
         _check_confirm_delete, limit=180),
    _web("web-tabs", "Open the Billing section, set the plan to Team and the seats to 12, then press Save in that section.",
         _check_tabs, limit=180),
    _web("web-async-search", "Search the trail finder for osprey and open the result named exactly 'Osprey ridge trail'.",
         _check_async_search, limit=180),
    _web("web-reveal-enter", "Get the pairing code from the page, enter it in the Pairing code field and press Pair device.",
         _check_reveal, limit=180),
    Task("calc-long", "Calculate (37 × 12 + 159) ÷ 9 in Calculator and tell me the result.",
         "Calculator", "calc", 150, expect="67", check_fn=_check_calc),
]

BY_ID: Dict[str, Task] = {t.id: t for t in TASKS + HARD_TASKS}


def select_tasks(spec: str) -> List[Task]:
    """`all` is the original ten, `hard` the harder seven, `all+hard` both."""
    named = {"all": TASKS, "hard": HARD_TASKS, "all+hard": TASKS + HARD_TASKS}
    if spec.strip() in named:
        return list(named[spec.strip()])
    out = []
    for tid in [s.strip() for s in spec.split(",") if s.strip()]:
        if tid not in BY_ID:
            raise SystemExit(f"unknown task '{tid}'. Known: {', '.join(BY_ID)}")
        out.append(BY_ID[tid])
    return out
