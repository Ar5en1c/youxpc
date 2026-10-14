# codex-v3

Fourth benchmark pass: three tool stacks, seventeen tasks, two trials planned.

- `runs.as-recorded.jsonl`: the 102 rows exactly as the harness wrote them.
- `runs.jsonl`: the same rows, with the 46 second-trial runs that ended in Codex's quota message marked
  `infra_failure` (the harness of the day did not recognise that message). Nothing else is changed.
- `trial1.jsonl`: the 51 first-trial rows, the complete trial that `bench/RESULTS.md` reports.
- `strict-summary.md`: `analyze.py` over `trial1.jsonl`.
- Raw agent output is not in the repository (see the note in `bench/RESULTS.md`).
