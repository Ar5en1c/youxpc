#!/usr/bin/env python3
"""Build docs/index.html, the project page, from recorded benchmark runs.

Everything the page shows as a result or a replay is read from bench/results:
nothing is typed in by hand. Run it again after a new benchmark pass.

  python3 scripts/build_site.py [--repo owner/name]
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESULTS = ROOT / "bench" / "results"
PAGES = ROOT / "bench" / "pages"
import sys
sys.path.insert(0, str(ROOT / "bench"))
import tasks as bench_tasks  # noqa: E402

OTHERS = RESULTS / "others-haiku-v1"       # YouxPC, Cua Driver, Peekaboo, Playwright MCP
UPSTREAM = RESULTS / "claude-haiku-v1"     # Ghost OS
MODEL = "Claude Haiku 5.5"

TOOLS = [  # key, label, results dir, system name, note
    ("youxpc", "YouxPC", OTHERS, "youxpc-haiku", ""),
    ("playwright", "Playwright MCP 0.0.83", OTHERS, "playwright-haiku", "web pages only; its own headless browser"),
    ("cua", "Cua Driver 0.35.2", OTHERS, "cua-haiku", ""),
    ("ghost", "Ghost OS 2.2.1", UPSTREAM, "ghostos-haiku", "the project YouxPC was forked from"),
    ("peekaboo", "Peekaboo 4.9.2", OTHERS, "peekaboo-fg-haiku", "started with --allow-foreground"),
]
REPLAYS = [  # task, trial, label, page file (None = the drawn Calculator)
    ("web-long-form", 1, "Fill in a form", "web-long-form.html"),
    ("web-rows", 3, "Pick the right row", "web-rows.html"),
    ("calc-multiply", 2, "Use Calculator", None),
]


def rows(path: Path):
    return [r for r in map(json.loads, (path / "runs.jsonl").read_text().splitlines()) if not r.get("infra_failure")]


def strict(r) -> bool:
    return bool(r["success"]) and (not r["task"].startswith("calc-") or r.get("desktop_evidence") is True)


def trace(task: str, trial: int):
    """Tool calls with their results, and what the model said, from one recorded run."""
    calls, by_id, said = [], {}, []
    # The published, cleaned copy of the run (scripts/publish_traces.py).
    for line in (OTHERS / "traces" / "youxpc-haiku" / f"{task}-t{trial}.jsonl").read_text().splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        for block in (event.get("message") or {}).get("content") or []:
            if not isinstance(block, dict):
                continue
            if event.get("type") == "assistant" and block.get("type") == "tool_use":
                by_id[block["id"]] = len(calls)
                calls.append({"tool": block["name"].split("__")[-1], "args": block.get("input") or {}, "result": ""})
            elif event.get("type") == "assistant" and block.get("type") == "text" and block.get("text", "").strip():
                said.append(block["text"].strip())
            elif event.get("type") == "user" and block.get("type") == "tool_result" and block.get("tool_use_id") in by_id:
                content = block.get("content")
                text = content if isinstance(content, str) else " ".join(x.get("text", "") for x in content if isinstance(x, dict))
                calls[by_id[block["tool_use_id"]]]["result"] = text
    return calls, said


def page_part(listing: str):
    """The part of a browser snapshot that describes the page, and how many other lines there were."""
    lines = listing.split("\n")
    start = next((i for i, l in enumerate(lines) if l.startswith("web ")), None)
    if start is None:
        end = next((i for i, l in enumerate(lines) if l.strip() == "toolbar"), len(lines))
        return "\n".join(lines[:end]), len(lines) - end
    end = next((i for i in range(start + 1, len(lines)) if lines[i] and not lines[i].startswith(" ")), len(lines))
    return "\n".join([lines[0]] + lines[start:end]), len(lines) - (end - start) - 1


def clean(text: str) -> str:
    """Local server ports differ per run and mean nothing to a reader."""
    return re.sub(r"127\.0\.0\.1:\d+", "127.0.0.1", text)


def inline_page(name: str) -> str:
    html = (PAGES / name).read_text()
    stub = "<script>window.rec = function () {};</script>"   # the page reports actions to the benchmark recorder; here there is none
    return html.replace('<script src="_common.js"></script>', stub)


# Plain names for the per-task table on the page.
SHORT_NAME = {
    "calc-multiply": "47 × 19 in Calculator",
    "calc-chain": "(128 + 256) ÷ 4 in Calculator",
    "textedit-type": "Type a code into TextEdit",
    "web-click": "Click one button",
    "web-form": "Fill two fields and submit",
    "web-checkbox-select": "Checkbox, dropdown, save",
    "web-read": "Read a code off the page",
    "web-scroll": "Scroll, then confirm an order",
    "web-dialog": "Rename through a dialog",
    "web-wizard": "Three-step form",
    "web-rows": "Approve one row, reject another",
    "web-long-form": "Seven-field registration form",
    "web-confirm-delete": "Delete one draft, confirm",
    "web-tabs": "Tabs, a dropdown and a number",
    "web-async-search": "Search results that arrive late",
    "web-reveal-enter": "Copy a code that appears on click",
    "calc-long": "(37 × 12 + 159) ÷ 9 in Calculator",
}


def failed_run(sentence: dict) -> dict:
    """The one run YouxPC failed in the sixth pass, as recorded, so the page can show it rather than describe it."""
    calls, said = trace("web-rows", 2)
    listing = page_part(clean(calls[0]["result"]))[0].split("\n")
    first = next(i for i, l in enumerate(listing) if 'row "Marlow Quist"' in l)
    last = next(i for i, l in enumerate(listing) if "[e21]" in l)
    passed = runs = 0
    for d in (ROOT / "bench" / "results").iterdir():
        if not (d / "runs.jsonl").exists():
            continue
        for r in rows(d):
            if r["task"] == "web-rows" and r["system"] in ("youxpc-haiku", "youxpc-simple-haiku"):
                runs += 1
                passed += strict(r)
    do = next(c for c in calls if c["tool"] == "pc_do")
    return {"sentence": sentence["web-rows"], "listing": "\n".join(listing[first:last + 1]), "call": do["args"],
            "answer": clean(do["result"]), "said": next((t for t in said if "mistake" in t), said[-1]),
            "passed": passed, "runs": runs}


def build(repo: str) -> dict:
    sentence = {t.id: t.sentence for t in bench_tasks.TASKS + bench_tasks.HARD_TASKS}
    order = [t.id for t in bench_tasks.TASKS + bench_tasks.HARD_TASKS]
    data = {tool[0]: [r for r in rows(tool[2]) if r["system"] == tool[3]] for tool in TOOLS}

    replays = []
    youxpc = {(r["task"], r["trial"]): r for r in data["youxpc"]}
    for task, trial, label, page in REPLAYS:
        calls, said = trace(task, trial)
        run = youxpc[(task, trial)]
        assert strict(run), f"{task} trial {trial} did not pass; pick another run to replay"
        listing, hidden = page_part(calls[0]["result"])
        for call in calls:
            call["result"] = clean(call["result"])
            if call["tool"] == "pc_snapshot" and call is not calls[0]:
                call["result"] = page_part(call["result"])[0]
        replays.append({
            "id": task, "label": label, "sentence": sentence[task], "seconds": run["wall_seconds"],
            "toolCalls": run["tool_calls"], "calls": calls, "listing": clean(listing), "hidden": hidden,
            "said": said[-1] if said else "", "drawn": page is None,
            "page": inline_page(page) if page else (ROOT / "site" / "calculator.html").read_text(),
            "pointer": run.get("pointer_counts") or {},
        })

    hard = {t.id for t in bench_tasks.HARD_TASKS}
    race = []
    for task in order:
        entry = {"id": task, "sentence": sentence[task], "label": SHORT_NAME.get(task, task), "hard": task in hard, "tools": []}
        for key, label, _, _, note in TOOLS:
            runs = [r for r in data[key] if r["task"] == task]
            if not runs:
                entry["tools"].append({"key": key, "label": label, "none": True})
                continue
            entry["tools"].append({
                "key": key, "label": label, "seconds": round(sum(r["wall_seconds"] for r in runs) / len(runs), 1),
                "calls": round(sum(r["tool_calls"] or 0 for r in runs) / len(runs), 1),
                "passed": sum(strict(r) for r in runs), "runs": len(runs),
            })
        race.append(entry)

    def total(key, pick):
        runs = [r for r in data[key] if pick(r["task"])]
        if not runs:
            return None
        return {"passed": sum(strict(r) for r in runs), "runs": len(runs), "seconds": round(sum(r["wall_seconds"] for r in runs)),
                "calls": sum(r["tool_calls"] or 0 for r in runs), "tokens": sum(r["total_tokens"] or 0 for r in runs)}

    scopes = {"all": lambda t: True, "web": lambda t: t.startswith("web-")}
    table = {name: [dict(total(k, pick) or {}, key=k, label=label, note=note) for k, label, _, _, note in TOOLS if total(k, pick)
                    and not (name == "all" and k == "playwright")]
             for name, pick in scopes.items()}
    pointer = {"virtual": 0, "real": 0}
    for r in data["youxpc"]:
        counts = r.get("pointer_counts") or {}
        pointer["virtual"] += counts.get("virtual", 0)
        pointer["real"] += counts.get("system-returned", 0) + counts.get("system", 0)
    return {"repo": repo, "model": MODEL, "replays": replays, "race": race, "table": table, "pointer": pointer,
            "taskCount": len(order), "trials": 3, "failure": failed_run(sentence)}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default="Ar5en1c/youxpc", help="GitHub owner/name used in links and the install command")
    args = parser.parse_args()
    data = build(args.repo)
    template = (ROOT / "site" / "page.html.in").read_text()
    blob = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
    out = ROOT / "docs" / "index.html"
    out.write_text(template.replace("/*__DATA__*/null", blob).replace("__REPO__", args.repo))
    (ROOT / "docs" / ".nojekyll").write_text("")
    print(f"wrote {out} ({out.stat().st_size // 1024} KB): {len(data['replays'])} replays, {len(data['race'])} tasks")


if __name__ == "__main__":
    main()
