#!/usr/bin/env python3
"""Turn a runs JSONL into summary.md and summary.json.

  python3 bench/report.py bench/results/run1            # reads runs.jsonl
  python3 bench/report.py path/to/runs.jsonl --out dir

Rows with infra_failure (setup/checker could not run) are excluded from every
statistic and counted separately. If a key (system, task, trial) appears more than
once, the last row wins. null metrics are never imputed; statistics skip them and
state how many runs contributed.
"""
from __future__ import annotations

import argparse
import json
import statistics
from collections import OrderedDict
from pathlib import Path
from typing import Any, Dict, List, Optional


def load_rows(path: Path) -> List[Dict[str, Any]]:
    latest: "OrderedDict[tuple, Dict[str, Any]]" = OrderedDict()
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except ValueError:
            continue
        latest[(r["system"], r["task"], r["trial"])] = r
    return list(latest.values())


def _vals(rows, key) -> List[float]:
    return [r[key] for r in rows if isinstance(r.get(key), (int, float)) and not isinstance(r.get(key), bool)]


def _med(v): return statistics.median(v) if v else None
def _mean(v): return statistics.mean(v) if v else None


def stat_block(rows: List[Dict[str, Any]]) -> Dict[str, Any]:
    n = len(rows)
    ok = [r for r in rows if r.get("success")]
    out: Dict[str, Any] = {"runs": n, "successes": len(ok),
                           "success_rate": (len(ok) / n) if n else None}
    for label, subset in (("successful", ok), ("all", rows)):
        out[f"wall_seconds_median_{label}"] = _med(_vals(subset, "wall_seconds"))
        out[f"wall_seconds_mean_{label}"] = _mean(_vals(subset, "wall_seconds"))
        out[f"total_tokens_median_{label}"] = _med(_vals(subset, "total_tokens"))
        out[f"tool_calls_median_{label}"] = _med(_vals(subset, "tool_calls"))
        out[f"n_with_tokens_{label}"] = len(_vals(subset, "total_tokens"))
        out[f"n_with_tool_calls_{label}"] = len(_vals(subset, "tool_calls"))
    costs = _vals(rows, "cost_usd")
    out["cost_usd_total"] = sum(costs) if costs else None
    out["runs_with_cost"] = len(costs)
    ptr = {"virtual": 0, "system-returned": 0, "system": 0}
    have = 0
    for r in rows:
        pc = r.get("pointer_counts")
        if isinstance(pc, dict):
            have += 1
            for k in ptr:
                ptr[k] += int(pc.get(k, 0))
    out["pointer_counts_total"] = ptr if have else None
    out["runs_with_pointer_data"] = have
    ev = [r["desktop_evidence"] for r in rows if isinstance(r.get("desktop_evidence"), bool)]
    out["desktop_evidence_true"] = sum(ev) if ev else None
    out["desktop_evidence_of"] = len(ev)
    out["timeouts"] = sum(1 for r in rows if r.get("timed_out"))
    return out


def build_summary(rows: List[Dict[str, Any]]) -> Dict[str, Any]:
    valid = [r for r in rows if not r.get("infra_failure")]
    infra = [r for r in rows if r.get("infra_failure")]
    systems = list(OrderedDict.fromkeys(r["system"] for r in valid))
    tasks = list(OrderedDict.fromkeys(r["task"] for r in valid))
    summary: Dict[str, Any] = {
        "total_rows": len(rows), "valid_runs": len(valid), "infra_failures": len(infra),
        "dry_run": any(r.get("dry_run") for r in rows),
        "systems": {s: stat_block([r for r in valid if r["system"] == s]) for s in systems},
        "per_task": {}, "infra_failure_list": [
            {"system": r["system"], "task": r["task"], "trial": r["trial"], "error": r.get("error") or r.get("check_note")}
            for r in infra],
    }
    for t in tasks:
        summary["per_task"][t] = {}
        for s in systems:
            sub = [r for r in valid if r["task"] == t and r["system"] == s]
            if sub:
                summary["per_task"][t][s] = stat_block(sub)
    return summary


def _f(v, nd=1, suffix=""):
    return "n/a" if v is None else f"{v:.{nd}f}{suffix}"


def _i(v):
    return "n/a" if v is None else f"{v:,.0f}"


def render_md(sm: Dict[str, Any]) -> str:
    L: List[str] = ["# Benchmark summary", ""]
    if sm["dry_run"]:
        L += ["> DRY RUN: produced with a fake agent and fake desktop. Success and time say nothing "
              "about any real system; token, cost and tool-call fields are null by design.", ""]
    L += [f"Valid runs: {sm['valid_runs']}. Infrastructure failures excluded: {sm['infra_failures']}. "
          "n/a means the system did not expose that number; nothing is estimated.", ""]
    L += ["## Per system", "",
          "| System | Success | Wall s median (successful) | Wall s median (all runs) | Wall s mean (all runs) "
          "| Total tokens median (successful) | Total tokens median (all runs) | Tool calls median (successful) "
          "| Tool calls median (all runs) | Total cost USD | Timeouts |",
          "|---|---|---|---|---|---|---|---|---|---|---|"]
    for s, b in sm["systems"].items():
        cost = "n/a" if b["cost_usd_total"] is None else \
            f"${b['cost_usd_total']:.4f} ({b['runs_with_cost']}/{b['runs']} runs reported)"
        tk_s = f"{_i(b['total_tokens_median_successful'])} (n={b['n_with_tokens_successful']})"
        tk_a = f"{_i(b['total_tokens_median_all'])} (n={b['n_with_tokens_all']})"
        tc_s = f"{_f(b['tool_calls_median_successful'], 1)} (n={b['n_with_tool_calls_successful']})"
        tc_a = f"{_f(b['tool_calls_median_all'], 1)} (n={b['n_with_tool_calls_all']})"
        L.append(f"| {s} | {b['successes']}/{b['runs']} ({_f(100 * b['success_rate'], 0, '%')}) "
                 f"| {_f(b['wall_seconds_median_successful'])} | {_f(b['wall_seconds_median_all'])} "
                 f"| {_f(b['wall_seconds_mean_all'])} | {tk_s} | {tk_a} | {tc_s} | {tc_a} | {cost} | {b['timeouts']} |")
    L += ["", "Medians are labelled by population: *successful* = runs where the checker passed, "
              "*all runs* = every valid run including failures and timeouts. (n=k) is the number of runs "
              "that reported that metric.", ""]
    ptr_lines = [(s, b) for s, b in sm["systems"].items() if b["pointer_counts_total"]]
    if ptr_lines:
        L += ["## Pointer paths (YouxPC systems)", ""]
        for s, b in ptr_lines:
            p = b["pointer_counts_total"]
            L.append(f"- {s}: virtual {p['virtual']}, system-returned {p['system-returned']}, "
                     f"system {p['system']} (parsed from {b['runs_with_pointer_data']} runs)")
        L.append("")
    ev_lines = [(s, b) for s, b in sm["systems"].items() if b["desktop_evidence_true"] is not None]
    if ev_lines:
        L += ["## Desktop evidence (Calculator / TextEdit read-back)", ""]
        for s, b in ev_lines:
            L.append(f"- {s}: {b['desktop_evidence_true']}/{b['desktop_evidence_of']} runs show the expected text on screen")
        L += ["", "Success for calculator tasks follows the final answer (as specified); this line is the "
                  "independent on-screen check.", ""]
    systems = list(sm["systems"])
    L += ["## Per task (successes/trials, median wall seconds over all runs)", "",
          "| Task | " + " | ".join(systems) + " |", "|---|" + "---|" * len(systems)]
    for t, cols in sm["per_task"].items():
        cells = []
        for s in systems:
            b = cols.get(s)
            cells.append("-" if not b else f"{b['successes']}/{b['runs']} · {_f(b['wall_seconds_median_all'])}s")
        L.append(f"| {t} | " + " | ".join(cells) + " |")
    if sm["infra_failure_list"]:
        L += ["", "## Infrastructure failures (excluded)", ""]
        L += [f"- {x['system']} {x['task']} t{x['trial']}: {x['error']}" for x in sm["infra_failure_list"]]
    return "\n".join(L) + "\n"


def generate(input_path: Path, out_dir: Path, stem: str = "summary") -> Dict[str, Any]:
    sm = build_summary(load_rows(Path(input_path)))
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / f"{stem}.md").write_text(render_md(sm))
    (out_dir / f"{stem}.json").write_text(json.dumps(sm, indent=2))
    return sm


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path", type=Path, help="results directory or runs .jsonl file")
    ap.add_argument("--out", type=Path)
    a = ap.parse_args()
    src = a.path / "runs.jsonl" if a.path.is_dir() else a.path
    out = a.out or (a.path if a.path.is_dir() else a.path.parent)
    generate(src, out)
    print(f"wrote {out}/summary.md and summary.json")


if __name__ == "__main__":
    main()
