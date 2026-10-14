"""Strict summary of one or more results files.

`report.py` counts a run as a success when the task checker passed. That is too
generous for the two Calculator tasks: a model can answer 47 x 19 from memory
without touching the app. This script applies one extra rule and says so:

  A Calculator run counts only if the Calculator display showed the result
  (`desktop_evidence` is true). The other tasks are judged by what the test page
  recorded, or by the answer for the read-only task, exactly as the checker did.

Usage: python3 bench/analyze.py bench/results/<name>/runs.jsonl [more.jsonl ...] [--md out.md]
"""
from __future__ import annotations

import json
import statistics
import sys
from collections import defaultdict
from pathlib import Path


def strict_success(row: dict) -> bool:
    if not row.get("success"):
        return False
    if row["task"].startswith("calc-"):
        return row.get("desktop_evidence") is True
    return True


def median(values):
    values = [v for v in values if v is not None]
    return statistics.median(values) if values else None


def fmt(value, digits=0):
    if value is None:
        return "n/a"
    return f"{value:,.{digits}f}"


def main(argv):
    out_md = None
    paths = []
    it = iter(argv)
    for arg in it:
        if arg == "--md":
            out_md = next(it)
        else:
            paths.append(arg)
    rows = []
    for path in paths:
        for line in Path(path).read_text().splitlines():
            if line.strip():
                rows.append(json.loads(line))
    rows = [r for r in rows if not r.get("infra_failure") and not r.get("dry_run")]

    by_system = defaultdict(list)
    for r in rows:
        by_system[r["system"]].append(r)
    tasks = sorted({r["task"] for r in rows})

    lines = []
    lines.append("| System | Tasks passed | Median time, passed runs (s) | Median tokens, passed runs | Median tool calls | Timeouts |")
    lines.append("|---|---|---|---|---|---|")
    for system, runs in by_system.items():
        passed = [r for r in runs if strict_success(r)]
        lines.append("| {} | {}/{} | {} | {} | {} | {} |".format(
            system, len(passed), len(runs),
            fmt(median(r["wall_seconds"] for r in passed), 1),
            fmt(median(r.get("total_tokens") for r in passed)),
            fmt(median(r.get("tool_calls") for r in passed)),
            sum(1 for r in runs if r.get("timed_out")),
        ))
    lines.append("")
    systems = list(by_system)
    lines.append("| Task | " + " | ".join(systems) + " |")
    lines.append("|---|" + "---|" * len(systems))
    for task in tasks:
        cells = []
        for system in systems:
            runs = [r for r in by_system[system] if r["task"] == task]
            if not runs:
                cells.append("-")
                continue
            ok = sum(1 for r in runs if strict_success(r))
            secs = median(r["wall_seconds"] for r in runs)
            toks = median(r.get("total_tokens") for r in runs)
            cells.append(f"{ok}/{len(runs)} · {fmt(secs, 0)}s · {fmt(toks)} tok")
        lines.append(f"| {task} | " + " | ".join(cells) + " |")

    # Pointer paths for YouxPC arms.
    pointer_lines = []
    for system, runs in by_system.items():
        totals = defaultdict(int)
        for r in runs:
            for key, count in (r.get("pointer_counts") or {}).items():
                totals[key] += count
        if sum(totals.values()):
            total = sum(totals.values())
            pointer_lines.append(f"| {system} | {totals['virtual']} | {totals['system-returned']} | {totals['system']} | "
                                 f"{100 * totals['virtual'] / total:.0f}% |")
    if pointer_lines:
        lines.append("")
        lines.append("| System | Actions without the pointer | Pointer borrowed and returned | Pointer moved | Share without pointer |")
        lines.append("|---|---|---|---|---|")
        lines += pointer_lines

    text = "\n".join(lines)
    print(text)
    if out_md:
        Path(out_md).write_text(text + "\n")


if __name__ == "__main__":
    main(sys.argv[1:])
