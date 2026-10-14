# YouxPC benchmark harness

Compares the same 10 desktop tasks across agent/tool "systems". Python 3 standard library only.

## Systems

| Name | What runs |
|---|---|
| `youxpc-haiku` | `claude -p` (model alias `haiku`) with only the YouxPC MCP server, `YOUXPC_ALLOW_APPS` set to the task's app |
| `ghostos-haiku` | identical command, MCP server is upstream Ghost OS (`--ghostos-bin`, args via `--ghostos-args`, default `mcp`) |
| `codex` | `codex exec --skip-git-repo-check -m gpt-6-luna --color never -o <file> "<prompt>"` |
| `youxpc-ollama:<model>` | a plain tool-calling loop against Ollama `/api/chat` executing calls through YouxPC over MCP |

A new system is one class in `systems/` that subclasses `System`, implements `matches(name)` and `run(ctx)`, and is decorated with `@register`; import it in `systems/__init__.py`.

### Claude flags and why

```
claude -p --model haiku --output-format stream-json --verbose \
  --mcp-config <run>.mcp.json --strict-mcp-config \
  --tools "" --allowedTools mcp__<server> --permission-mode dontAsk \
  --no-session-persistence --disable-slash-commands --max-budget-usd 1
```
The prompt is written to stdin, because `--mcp-config`, `--tools` and `--allowedTools` are variadic and would swallow a positional prompt.
`--strict-mcp-config` removes every other MCP server. `--tools ""` removes Bash, Read, Edit, WebFetch and the rest. `--allowedTools mcp__<server>` pre-approves exactly that server and `dontAsk` denies everything else instead of prompting. `stream-json` (not plain `json`) is used because it exposes tool calls and tool results for counting; its final `result` event carries `usage` and `total_cost_usd`. Run from an empty scratch directory so no project CLAUDE.md or memory loads. The harness removes `CLAUDECODE` from the child environment so the CLI does not refuse to nest. `--max-turns` does not exist in claude 2.1.293; runs are bounded by the wall-clock timeout and `--max-budget-usd` (pass `--claude-max-turns N` if your version has it).

## What is measured

Per run (`runs.jsonl`): task, system, trial, success, wall seconds (agent process only; setup, checker and teardown excluded), tool calls, input/output/total tokens, cost USD, final answer, error/timeout note, pointer-path counts, model, and `desktop_evidence`.

| System | tool calls | tokens | cost | pointer counts |
|---|---|---|---|---|
| claude systems | counted from `tool_use` blocks | from final `result.usage`; `input_tokens` = uncached + cache-read + cache-creation, parts kept in `extra` | `total_cost_usd` as the CLI reports it | YouxPC only, parsed from tool results |
| codex | null | total only, from "tokens used" | null | null |
| ollama | counted executed calls | sums of `prompt_eval_count` / `eval_count` | null (local) | parsed from tool results |

Anything a system does not expose is `null`, never estimated. Reports label each median as over successful runs or over all runs and show how many runs contributed (n=k).

Success comes from checkers, not agent claims: web tasks read the recorder's JSONL (`records/<system>/<task>-t<N>.jsonl`), TextEdit is read back through the YouxPC MCP server (`pc_read`, fallback `pc_snapshot`), and answer tasks (`calc-*`, `web-read`) look for the number as a standalone token in the final answer. For calculator tasks the Calculator display is also read and stored as `desktop_evidence`, because a model could answer 47 x 19 without opening the app.

Not measured: reasoning quality in isolation, cost on subscription plans (the CLI cost is a computed figure), model latency separate from tool latency, anything on Codex's internals.

## Safety design

- A real run requires `--yes`. `--dry-run` uses a fake agent and `FakeDesktop`; it launches nothing, and only talks to the local page server. Dry-run results go to `runs.dryrun.jsonl` / `summary.dryrun.*`, never into real results.
- Calculator and TextEdit are only driven if the harness started them (a pre-existing instance makes the run an infrastructure failure unless `--allow-preexisting-apps`, in which case it is never quit). Only PIDs the harness started are terminated.
- Brave runs as a separate instance: `open -na "Brave Browser" --args --user-data-dir=<mkdtemp> --no-first-run --no-default-browser-check --new-window <url>`. Teardown kills exactly the processes whose command line contains that `--user-data-dir=<dir>` argument, then deletes the profile. Chrome is never touched.
- Typed strings are inert tokens (`quartz-4821`, `basalt-77`, `cedar-305`, ...). Pages are served only on 127.0.0.1.
- Each run has a hard timeout (per-task 120-240 s, override with `--timeout`); on expiry the agent's whole process group is killed. `<out>/STOP` stops cleanly before the next run; Ctrl-C tears down the current run.
- Codex ignores `YOUXPC_ALLOW_APPS`, so it is not app-restricted. Ghost OS has no allow-list either.

## Reproduce

```
cd youxpc        # the repository root
python3 -m unittest discover bench/tests                   # pure Python, no desktop
python3 bench/run.py --list
python3 bench/run.py --dry-run --systems youxpc-haiku,codex --tasks all --trials 1 --out /tmp/bench-dry

# real run (drives the desktop; nothing else should be using it)
python3 bench/run.py --yes --systems youxpc-haiku,ghostos-haiku --tasks all --trials 2 \
    --ghostos-bin /path/to/ghost --out bench/results/run1
python3 bench/run.py --yes --systems 'youxpc-ollama:qwen3:1.7b' --tasks calc-multiply,web-click --out bench/results/run1
python3 bench/report.py bench/results/run1                 # regenerate summary.md / summary.json
```
Re-running the same command resumes: runs already in `runs.jsonl` are skipped (setup/checker infrastructure failures are retried). Runs are ordered trial -> task -> system, strictly sequential. Raw CLI output, MCP configs and Ollama tool transcripts are kept in `<out>/raw/`.

Layout: `run.py` CLI, `report.py`, `mcp_client.py`, `server.py` + `pages/`, `tasks.py`, `desktop.py` (all real-desktop code), `procutil.py`, `systems/`, `tests/`.

## Systems added after the first version

- `codex-youxpc`, `codex-youxpc-simple`, `codex-ghostos` (`systems/codex_mcp.py`): the
  Codex CLI is the model harness and the same OpenAI model drives each MCP server, with
  Codex's own plugins and user configuration switched off for the run
  (`--ignore-user-config --disable plugins`) and MCP tool calls approved by Codex's
  automatic reviewer (`--approve-for-me`). Together with `codex` (Codex's own computer
  use) this compares tool stacks with the model held constant.
- `youxpc-simple-ollama:<model>`, `youxpc-text-ollama:<model>`,
  `youxpc-simple-text-ollama:<model>` (`systems/ollama.py`): the simple profile,
  and a text protocol for models Ollama lists without tool-calling support.

## Strict scoring

`analyze.py` reports the numbers used in the project README. It applies one rule on top
of the task checkers: a Calculator run counts only if the Calculator display showed the
result, because a model can answer arithmetic without using the app.

## What could not be measured

- Claude models: the headless `claude -p` CLI could not authenticate from the session
  that ran the benchmark. The `youxpc-haiku` and `ghostos-haiku` systems are implemented
  but have no results.
- Codex's own computer use on these tasks: it refused each app because the per-app
  approval it needs from the user was not given during the unattended run. Those rows
  record the refusal; they are not a measure of what it can do once approved.
