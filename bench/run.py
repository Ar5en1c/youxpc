#!/usr/bin/env python3
"""Benchmark CLI. Runs strictly one task at a time (one screen).

  python3 bench/run.py --list
  python3 bench/run.py --dry-run --systems youxpc-haiku,codex --tasks all --trials 1 --out /tmp/x
  python3 bench/run.py --yes --systems youxpc-haiku,ghostos-haiku --tasks all --trials 2 \
        --ghostos-bin /path/to/ghost --out bench/results/run1

A real run drives the real desktop and requires --yes. Create <out>/STOP to stop
cleanly before the next run. Re-running the same command resumes.
"""
from __future__ import annotations

import argparse
import datetime
import json
import shutil
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))

import report  # noqa: E402
from desktop import FakeDesktop, MacDesktop, SetupError  # noqa: E402
from server import BenchServer  # noqa: E402
from systems import AgentContext, AgentResult, FakeSystem, Options, REGISTRY, make_system  # noqa: E402
from tasks import TASKS, Task, TaskContext, select_tasks  # noqa: E402

DEFAULT_YOUXPC = str(Path(__file__).resolve().parent.parent / ".build" / "debug" / "youxpc")
RUN_FILE, DRY_RUN_FILE = "runs.jsonl", "runs.dryrun.jsonl"


def safe(s: str) -> str:
    return "".join(c if c.isalnum() or c in "-_." else "_" for c in s)


def load_done(path: Path) -> Set[Tuple[str, str, int]]:
    done = set()
    if path.exists():
        for line in path.read_text().splitlines():
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if not r.get("infra_failure"):
                done.add((r["system"], r["task"], int(r["trial"])))
    return done


def execute_run(*, system, task: Task, trial: int, timeout: float, server: BenchServer,
                desktop, out: Path, dry_run: bool) -> Dict[str, Any]:
    label = f"{task.id}-t{trial}"
    sys_dir = safe(system.name)
    raw_dir = out / "raw" / sys_dir
    raw_dir.mkdir(parents=True, exist_ok=True)
    rec_path = out / "records" / sys_dir / f"{label}.jsonl"
    server.set_record_path(rec_path)
    scratch = Path(tempfile.mkdtemp(prefix="youxpc-bench-run-"))
    tctx = TaskContext(base_url=server.base_url, records=server.records, desktop=desktop,
                       scratch=scratch, dry_run=dry_run)
    row: Dict[str, Any] = {
        "task": task.id, "system": system.name, "trial": trial, "success": None,
        "wall_seconds": None, "tool_calls": None, "input_tokens": None, "output_tokens": None,
        "total_tokens": None, "cost_usd": None, "final_answer": None, "error": None,
        "timed_out": False, "pointer_counts": None, "desktop_evidence": None, "check_note": None,
        "model": None, "dry_run": dry_run, "infra_failure": False, "timeout_limit_s": timeout,
        "started_at": datetime.datetime.now().isoformat(timespec="seconds"), "extra": {},
    }
    handle = None
    try:
        try:
            handle = task.setup(tctx)
        except SetupError as e:
            row.update(error=f"setup failed: {e}", infra_failure=True)
            return row
        actx = AgentContext(task=task, prompt=task.prompt(), workdir=scratch, raw_dir=raw_dir,
                            label=label, timeout=timeout, base_url=server.base_url, desktop=desktop)
        t0 = time.monotonic()
        try:
            res: AgentResult = system.run(actx)
        except Exception as e:  # a crashing system is a result, not a harness crash
            res = AgentResult(error=f"agent exception: {type(e).__name__}: {e}")
        row["wall_seconds"] = round(time.monotonic() - t0, 2)
        if not dry_run:
            time.sleep(1.0)  # let in-flight page POSTs land
        for k in ("final_answer", "tool_calls", "input_tokens", "output_tokens", "total_tokens",
                  "cost_usd", "pointer_counts", "error", "timed_out", "model"):
            row[k] = getattr(res, k)
        row["extra"] = res.extra
        if res.extra.get("provider_unavailable"):
            # Not a result. Marked so that summaries leave it out and a later run repeats it.
            row.update(success=False, check_note="model provider refused the run (quota or rate limit)",
                       infra_failure=True)
            return row
        try:
            cr = task.check(tctx, res.final_answer or "")
            row.update(success=cr.success, check_note=cr.note, desktop_evidence=cr.evidence)
        except SetupError as e:
            row.update(success=False, check_note=f"checker failed: {e}", infra_failure=True)
        except Exception as e:
            row.update(success=False, check_note=f"checker exception: {type(e).__name__}: {e}")
        return row
    finally:
        try:
            task.teardown(tctx, handle)
        except Exception as e:
            row["extra"] = dict(row.get("extra") or {}, teardown_error=str(e))
        shutil.rmtree(scratch, ignore_errors=True)
        server.set_record_path(None)


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--systems", default="youxpc-haiku")
    ap.add_argument("--tasks", default="all")
    ap.add_argument("--trials", type=int, default=1)
    ap.add_argument("--out", type=Path, help="results directory")
    ap.add_argument("--timeout", type=float, default=None,
                    help="hard per-run timeout in seconds (default: per-task limit, 120-240; most 150-180)")
    ap.add_argument("--dry-run", action="store_true", help="fake agent + fake desktop; touches nothing")
    ap.add_argument("--dry-run-fail", default="", help="comma list of task ids the fake agent gets wrong")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--yes", action="store_true", help="confirm a REAL run that drives the desktop")
    ap.add_argument("--allow-preexisting-apps", action="store_true",
                    help="drive Calculator/TextEdit even if already running (never quit then)")
    ap.add_argument("--youxpc-bin", default=DEFAULT_YOUXPC)
    ap.add_argument("--ghostos-bin")
    ap.add_argument("--ghostos-args", default="mcp", help="args after the ghost binary (default: mcp)")
    ap.add_argument("--claude-bin", default="claude")
    ap.add_argument("--claude-model", default="haiku")
    ap.add_argument("--claude-max-turns", type=int, default=None)
    ap.add_argument("--max-budget-usd", type=float, default=1.0)
    ap.add_argument("--codex-bin", default="codex")
    ap.add_argument("--codex-model", default="gpt-6-luna")
    ap.add_argument("--ollama-url", default="http://localhost:11434")
    ap.add_argument("--max-steps", type=int, default=25, help="Ollama loop: max model calls")
    ap.add_argument("--num-ctx", type=int, default=16384)
    ap.add_argument("--max-result-chars", type=int, default=12000)
    return ap


def do_list() -> None:
    print("Tasks:")
    for t in TASKS:
        print(f"  {t.id:20s} {t.app_name:14s} limit {t.time_limit:3d}s  {t.sentence}")
    print("\nSystems:")
    for c in REGISTRY:
        print(f"  {', '.join(c.examples):26s} {c.description}")


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    if args.list:
        do_list()
        return 0
    if not args.out:
        print("--out is required", file=sys.stderr)
        return 2
    if not args.dry_run and not args.yes:
        print("This drives the real desktop. Re-run with --yes (or use --dry-run).", file=sys.stderr)
        return 2
    opts = Options(youxpc_bin=args.youxpc_bin, ghostos_bin=args.ghostos_bin, ghostos_args=args.ghostos_args,
                   claude_bin=args.claude_bin, claude_model=args.claude_model,
                   claude_max_turns=args.claude_max_turns, max_budget_usd=args.max_budget_usd,
                   codex_bin=args.codex_bin, codex_model=args.codex_model, ollama_url=args.ollama_url,
                   max_steps=args.max_steps, num_ctx=args.num_ctx, max_result_chars=args.max_result_chars)
    names = [s.strip() for s in args.systems.split(",") if s.strip()]
    tasks = select_tasks(args.tasks)
    if args.dry_run:
        fails = {s for s in args.dry_run_fail.split(",") if s}
        systems = [FakeSystem(n, opts, fails) for n in names]
        for n in names:
            make_system(n, opts)  # validates the name even in dry-run
        desktop = FakeDesktop()
    else:
        systems = [make_system(n, opts) for n in names]
        problems = [f"{s.name}: {p}" for s in systems for p in s.preflight()]
        if problems:
            print("Preflight failed:\n  " + "\n  ".join(problems), file=sys.stderr)
            return 2
        desktop = MacDesktop(opts.youxpc_bin, confirmed=True, allow_preexisting=args.allow_preexisting_apps)
        if not Path(opts.youxpc_bin).exists():
            print(f"youxpc binary missing: {opts.youxpc_bin} (needed by checkers)", file=sys.stderr)
            return 2

    # Agents run with a scratch working directory, so every path handed to them must be absolute.
    out: Path = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    results_path = out / (DRY_RUN_FILE if args.dry_run else RUN_FILE)
    done = load_done(results_path)
    server = BenchServer().start()
    total = len(tasks) * len(systems) * args.trials
    print(f"{'DRY RUN ' if args.dry_run else ''}{total} runs planned, {len(done)} already recorded; "
          f"results: {results_path}")
    n = 0
    try:
        for trial in range(1, args.trials + 1):
            for task in tasks:
                for system in systems:
                    n += 1
                    if (system.name, task.id, trial) in done:
                        print(f"[{n}/{total}] skip {system.name} {task.id} t{trial} (already done)")
                        continue
                    if (out / "STOP").exists():
                        print("STOP file found; stopping.")
                        return 0
                    timeout = args.timeout or float(task.time_limit)
                    print(f"[{n}/{total}] {system.name} {task.id} t{trial} (limit {timeout:.0f}s) ...", flush=True)
                    row = execute_run(system=system, task=task, trial=trial, timeout=timeout, server=server,
                                      desktop=desktop, out=out, dry_run=args.dry_run)
                    with open(results_path, "a") as fh:
                        fh.write(json.dumps(row, ensure_ascii=False) + "\n")
                    flag = "INFRA-FAIL" if row["infra_failure"] else ("PASS" if row["success"] else "FAIL")
                    print(f"    {flag} wall={row['wall_seconds']}s {row.get('error') or row.get('check_note') or ''}")
                    if (row.get("extra") or {}).get("provider_unavailable"):
                        print("The model provider refused this run (quota or rate limit). Stopping; "
                              "re-run the same command later to resume.")
                        return 3
    except KeyboardInterrupt:
        print("interrupted; current run was torn down. Re-run to resume.")
        return 130
    finally:
        server.stop()
        stem = "summary.dryrun" if args.dry_run else "summary"
        if results_path.exists():
            report.generate(results_path, out, stem)
            print(f"wrote {out / (stem + '.md')} and {out / (stem + '.json')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
