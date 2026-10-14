import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

import helpers  # noqa: F401
from helpers import BENCH
from desktop import MacDesktop, pids_with_arg
from procutil import run_with_timeout
import report


class ProcTests(unittest.TestCase):
    def test_timeout_kills_whole_tree(self):
        d = Path(tempfile.mkdtemp())
        script = f"sleep 300 & echo $! > {d}/child.pid; wait"
        info = run_with_timeout(["sh", "-c", script], timeout=1.0, stdout_path=str(d / "o"),
                                stderr_path=str(d / "e"))
        self.assertTrue(info.timed_out)
        child = int((d / "child.pid").read_text())
        time.sleep(0.3)
        with self.assertRaises(ProcessLookupError):
            os.kill(child, 0)

    def test_normal_exit_and_stdin(self):
        d = Path(tempfile.mkdtemp())
        info = run_with_timeout(["cat"], timeout=5, stdin_text="hello", stdout_path=str(d / "o"),
                                stderr_path=str(d / "e"))
        self.assertFalse(info.timed_out)
        self.assertEqual((d / "o").read_text(), "hello")

    def test_missing_binary(self):
        d = Path(tempfile.mkdtemp())
        info = run_with_timeout(["/no/such/bin"], timeout=5, stdout_path=str(d / "o"), stderr_path=str(d / "e"))
        self.assertIsNotNone(info.spawn_error)


class DesktopTests(unittest.TestCase):
    PS = ("  101 /Applications/Brave Browser.app/Contents/MacOS/Brave Browser --user-data-dir=/tmp/p1 --no-first-run\n"
          "  102 /x/Brave Helper --type=renderer --user-data-dir=/tmp/p1\n"
          "  103 /x/Brave Browser --user-data-dir=/tmp/p10 --no-first-run\n"
          "  104 /Applications/Brave Browser.app/Contents/MacOS/Brave Browser\n")

    def test_pids_match_exact_profile_only(self):
        self.assertEqual(pids_with_arg(self.PS, "--user-data-dir=/tmp/p1"), [101, 102])
        self.assertEqual(pids_with_arg(self.PS, "--user-data-dir=/tmp/p10"), [103])

    def test_macdesktop_refuses_without_confirmation(self):
        with self.assertRaises(RuntimeError):
            MacDesktop("/bin/true")


class ReportTests(unittest.TestCase):
    def rows(self):
        def r(system, task, trial, ok, wall, toks, calls, cost, **kw):
            d = dict(system=system, task=task, trial=trial, success=ok, wall_seconds=wall, total_tokens=toks,
                     tool_calls=calls, cost_usd=cost, timed_out=False, infra_failure=False,
                     pointer_counts=None, desktop_evidence=None)
            d.update(kw)
            return d
        return [
            r("A", "t1", 1, True, 10, 1000, 4, 0.01, pointer_counts={"virtual": 3, "system-returned": 1, "system": 0}),
            r("A", "t1", 2, False, 30, 3000, 8, 0.03, pointer_counts={"virtual": 1, "system-returned": 0, "system": 2}),
            r("B", "t1", 1, True, 20, None, None, None),
            r("B", "t1", 2, True, 40, None, None, None),
            r("B", "t2", 1, False, None, None, None, None, infra_failure=True, error="setup failed"),
        ]

    def test_summary_numbers(self):
        sm = report.build_summary(self.rows())
        a, b = sm["systems"]["A"], sm["systems"]["B"]
        self.assertEqual((a["successes"], a["runs"]), (1, 2))
        self.assertEqual(a["wall_seconds_median_successful"], 10)
        self.assertEqual(a["wall_seconds_median_all"], 20)
        self.assertEqual(a["wall_seconds_mean_all"], 20)
        self.assertEqual(a["total_tokens_median_successful"], 1000)
        self.assertEqual(a["total_tokens_median_all"], 2000)
        self.assertAlmostEqual(a["cost_usd_total"], 0.04)
        self.assertEqual(a["pointer_counts_total"], {"virtual": 4, "system-returned": 1, "system": 2})
        self.assertIsNone(b["total_tokens_median_all"])      # never imputed
        self.assertIsNone(b["cost_usd_total"])
        self.assertEqual(sm["infra_failures"], 1)
        self.assertNotIn("t2", sm["per_task"])

    def test_last_row_wins_and_markdown(self):
        d = Path(tempfile.mkdtemp())
        rows = self.rows()
        retry = dict(rows[-1], infra_failure=False, success=True, wall_seconds=5, error=None)
        (d / "runs.jsonl").write_text("\n".join(json.dumps(x) for x in rows + [retry]))
        sm = report.generate(d / "runs.jsonl", d)
        self.assertEqual(sm["infra_failures"], 0)
        md = (d / "summary.md").read_text()
        self.assertIn("median (successful)", md)
        self.assertIn("median (all runs)", md)
        self.assertIn("1/2 (50%)", md)
        self.assertIn("n/a", md)
        self.assertTrue(json.loads((d / "summary.json").read_text())["systems"]["A"])


class DryRunEndToEnd(unittest.TestCase):
    def run_cli(self, *args):
        return subprocess.run([sys.executable, str(BENCH / "run.py"), *args], capture_output=True, text=True,
                              timeout=120)

    def test_dry_run_resume_and_guards(self):
        out = Path(tempfile.mkdtemp()) / "res"
        a = ["--dry-run", "--systems", "youxpc-haiku,codex", "--tasks", "all", "--trials", "1",
             "--dry-run-fail", "web-form", "--out", str(out)]
        p = self.run_cli(*a)
        self.assertEqual(p.returncode, 0, p.stderr + p.stdout)
        rows = [json.loads(x) for x in (out / "runs.dryrun.jsonl").read_text().splitlines()]
        self.assertEqual(len(rows), 20)
        self.assertTrue(all(r["dry_run"] for r in rows))
        failed = {(r["system"], r["task"]) for r in rows if not r["success"]}
        self.assertEqual(failed, {("youxpc-haiku", "web-form"), ("codex", "web-form")})
        self.assertTrue(all(r["total_tokens"] is None and r["cost_usd"] is None for r in rows))
        self.assertTrue((out / "summary.dryrun.md").exists())
        self.assertFalse((out / "runs.jsonl").exists())            # never mixes with real results
        p2 = self.run_cli(*a)                                      # resume: nothing new appended
        self.assertEqual(len((out / "runs.dryrun.jsonl").read_text().splitlines()), 20)
        self.assertIn("already done", p2.stdout)

    def test_real_run_needs_yes(self):
        p = self.run_cli("--systems", "youxpc-haiku", "--out", str(Path(tempfile.mkdtemp()) / "x"))
        self.assertEqual(p.returncode, 2)
        self.assertIn("--yes", p.stderr)

    def test_list(self):
        p = self.run_cli("--list")
        self.assertIn("web-wizard", p.stdout)
        self.assertIn("codex", p.stdout)


if __name__ == "__main__":
    unittest.main()
