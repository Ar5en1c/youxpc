# Benchmark results

Date: 13 October 2026. Machine: Apple M1, 16 GB, macOS 27. One machine, one day. Six passes, newest first.

## Sixth pass: other tools, same model

Peekaboo, Cua Driver and Playwright MCP are each somebody else's MCP server, so the same command (`claude -p` with `claude-haiku-5-5` and only that one server available) drove each of them on the same tasks, three trials each (`results/others-haiku-v1`, 243 runs, no infrastructure failures). YouxPC was run again alongside them on its current build. All of them ran with their default settings and no tuning, except where stated.

All seventeen tasks (51 runs each):

| Tool | Runs passed | Total time | Tool calls | Tokens | Cost reported by the CLI |
|---|---|---|---|---|---|
| YouxPC, default profile | 50 of 51 | 630 s | 216 | 2,050,398 | $0.088 |
| Cua Driver 0.35.2 | 51 of 51 | 1,287 s | 441 | 23,902,869 | $0.437 |
| Peekaboo 4.9.2, `--allow-foreground` | 41 of 51 | 1,897 s | 819 | 43,644,540 | $1.003 |
| Peekaboo 4.9.2, default (background only) | 22 of 51 | 1,905 s | 778 | 39,565,131 | $1.084 |
| Ghost OS 2.2.1 (fifth pass, earlier the same day) | 46 of 51 | 1,176 s | 699 | 9,007,227 | $0.259 |

The thirteen web tasks (39 runs each), which is all Playwright MCP can do:

| Tool | Runs passed | Total time | Tool calls | Tokens | Cost |
|---|---|---|---|---|---|
| Playwright MCP 0.0.83 (its own headless browser) | 39 of 39 | 448 s | 243 | 2,309,907 | $0.075 |
| YouxPC, default profile (a visible Brave window) | 38 of 39 | 465 s | 184 | 1,674,039 | $0.069 |
| Cua Driver | 39 of 39 | 913 s | 382 | 19,909,307 | $0.356 |
| Peekaboo, `--allow-foreground` | 29 of 39 | 1,436 s | 540 | 28,506,759 | $0.741 |

The four desktop-app tasks (12 runs each): every tool passed all twelve. YouxPC took 165 s and 32 tool calls, Cua Driver 374 s and 59, Peekaboo 461 s and 279.

Fixed context each tool adds for its tool list and instructions (characters divided by four): YouxPC simple about 1,000 tokens, YouxPC default 3,200, Playwright MCP 5,300, Ghost OS 8,300, Peekaboo 14,400, Cua Driver 49,000.

What this shows:

- **Cua Driver is as reliable as YouxPC on these tasks.** It passed every run. YouxPC took 51% less time, made 51% fewer tool calls, read 91% fewer tokens and cost 80% less. A large part of Cua Driver's token count is its tool list, sent on every model call.
- **On web pages, Playwright MCP and YouxPC are about level.** Playwright was 4% faster and passed every run; YouxPC made 24% fewer calls and read 28% fewer tokens. They are not doing the same job: Playwright drove its own headless browser, and YouxPC operated a real, visible browser window through the operating system, which is also how it reaches the toolbar, an extension's side panel and desktop apps.
- **Peekaboo did much worse here, and its setting matters.** Its server is background-only by default; in that mode it could not press buttons inside a web page (10 of 39 web runs) though it passed every desktop-app run. With `--allow-foreground` it passed 29 of 39 web runs. Its `web-click` failures with that flag are a click that reported failure but had registered, followed by a second click; the checker wants exactly one.
- **YouxPC's one failure was the model's.** On `web-rows` it clicked Approve where Reject was asked for, on the correct row; the listing was correct and the tool pressed what it was told to press. Over the two sessions on this day the default profile passed 101 of 102 runs.
- **Pointer.** All 259 YouxPC actions went through accessibility. This build has the text-field change made after the fifth pass.

Claude in Chrome (the browser extension) was also tried, but not with this harness, so it is not in the tables. A Claude Haiku 5.5 agent was given only the extension's tools and did each of the thirteen web tasks once in a new tab of the user's own Chrome. All thirteen passed by the same checkers (`results/claude-in-chrome-haiku`). It made 168 tool calls and took 399 s in total, but those figures include about five set-up calls per task, the agent's own start-up, and up to three tasks running at once, so they are not comparable with the tables above.

Caveats:

- Every other tool ran as installed, with default settings (plus one documented flag for Peekaboo). Their authors might configure them differently, and I have no experience tuning them. YouxPC has been worked over on these tasks for a day.
- I wrote the seven harder tasks and prepared YouxPC against them. Cua Driver and Playwright MCP passing all of them is the first evidence that those tasks are not simply shaped to YouxPC.
- One model, one machine, one day. Versions as stated.

Not compared: Codex's own computer use (no quota until November, and it needs per-app approval), and small local models.

## Fifth pass: Claude Haiku 5.5, seventeen tasks, three trials

YouxPC against Ghost OS, three complete trials (`results/claude-haiku-v1`, 153 runs, no infrastructure failures). The model is `claude-haiku-5-5` through `claude -p`, with only the MCP server under test available to it. YouxPC is the build after every fix described on this page except one (noted below). Same machine, same seventeen tasks and same scoring as the fourth pass.

| Tool stack | Runs passed | Total time | Tool calls | Tokens | Cost reported by the CLI |
|---|---|---|---|---|---|
| YouxPC, default profile | 51 of 51 | 629 s | 216 | 2,110,340 | $0.090 |
| YouxPC, simple profile | 51 of 51 | 638 s | 189 | 1,413,032 | $0.076 |
| Ghost OS 2.2.1 | 46 of 51 | 1,176 s | 699 | 9,007,227 | $0.259 |

Tokens are everything the model read, cached or not, plus what it wrote. Cost is the CLI's own figure, which prices cached tokens lower; the runs were made on a subscription, so it is a measure of size, not a bill.

Split by task set, and by trial:

| | YouxPC default | YouxPC simple | Ghost OS 2.2.1 |
|---|---|---|---|
| Original ten (30 runs) | 30 · 311 s · 101 calls | 30 · 340 s · 88 calls | 30 · 515 s · 296 calls |
| Harder seven (21 runs) | 21 · 317 s · 115 calls | 21 · 298 s · 101 calls | 16 · 661 s · 403 calls |
| Passed per trial (of 17) | 17, 17, 17 | 17, 17, 17 | 16, 15, 15 |

What this shows:

- **Speed and cost.** Against Ghost OS the default profile took 47% less time, made 69% fewer tool calls, read 77% fewer tokens and cost 65% less. The simple profile took 46% less time, read 84% fewer tokens and cost 71% less. The time gap is smaller than with `gpt-6-luna` (63%) because this model answers faster, so each saved call saves less.
- **Reliability.** Both YouxPC profiles passed every run. Ghost OS failed 5 of 51, in every trial, all on three of the harder tasks. On the ten short tasks all three stacks passed 30 of 30.
- **Pointer.** Of 268 actions in the default arm, 262 went through accessibility and 6 used the real pointer and put it back; 214 and 5 in the simple arm. All eleven were clicks on text fields. Those now go through accessibility as well (fixed after this pass, the one fix not in these numbers).

Ghost OS's five failures:

| Task | Trials | What happened |
|---|---|---|
| `web-rows` | 2 and 3 | Approved the first row's request before the right one. Six buttons share the name "Approve" and a click by name took the first. The model noticed and said so. |
| `web-async-search` | 1 and 2 | Opened "Osprey ridge trail (closed)", twice, before the result that was asked for. |
| `web-confirm-delete` | 3 | Could not get the deletion confirmed; nothing was deleted. |

How far the reliability result goes:

- It is a real difference on these tasks: 0 failures in 102 YouxPC runs against 5 in 51.
- The three tasks Ghost OS failed are ones I wrote, and I fixed YouxPC against all seven harder pages by hand before any model saw them. The failures are also exactly the cases those fixes target (controls that share a name; a confirm dialog). So the supported statement is "more reliable on tasks with repeated control names, near-duplicate names and confirm dialogs", not "more reliable in general".
- Nobody else has written tasks for this benchmark. That is the missing test.
- Three trials, one model, one machine, one day.

The fourth pass, below, used `gpt-6-luna` and an earlier YouxPC build; the three tasks YouxPC failed there (`calc-chain`, `web-long-form`, `calc-long`) passed three times out of three here in both profiles.

## Fourth pass: seventeen tasks, one trial

This pass used `gpt-6-luna` through the Codex CLI (`results/codex-v3`). It differs from the passes described further down in three ways: YouxPC has `pc_do` (several actions in one call) and the fixes listed in the last section; seven harder tasks were added to the ten; and only one trial per task is valid.

Same model and harness as before (`gpt-6-luna` through the Codex CLI), same machine. Seventeen tasks: the original ten plus `web-rows` (six rows with identical Approve and Reject buttons), `web-long-form` (seven fields, a pre-ticked checkbox to untick), `web-confirm-delete` (five identical Delete buttons and a confirm dialog), `web-tabs` (in-page tabs, a dropdown, a field), `web-async-search` (results arrive 0.7 s after typing; near-duplicate names), `web-reveal-enter` (a code that appears 1.2 s after a click) and `calc-long`.

Two trials were planned. The free ChatGPT plan's quota ran out during the second: 46 of its 51 runs ended with Codex's quota message and are not results. They are kept in `results/codex-v3/runs.jsonl`, marked as infrastructure failures, and are left out below; the file as the harness first wrote it is alongside. The first trial is complete for all three stacks.

| Tool stack | Tasks passed | Total time | Tool calls | Tokens, Codex's count | Input tokens read |
|---|---|---|---|---|---|
| YouxPC, default profile | 14 of 17 | 348 s | 49 | 364,833 | 1,928,315 |
| YouxPC, simple profile | 14 of 17 | 320 s | 47 | 280,817 | 1,424,500 |
| Ghost OS 2.2.1 | 13 of 17 | 929 s | 178 | 653,806 | 5,791,466 |

"Tokens, Codex's count" is uncached input plus output, which is what Codex reports as tokens used. "Input tokens read" is every token the model was sent, cached or not; Codex's own prompt is about 27,000 of them on every model call, so this column mostly counts model calls.

Split by task set:

| | YouxPC default | YouxPC simple | Ghost OS 2.2.1 |
|---|---|---|---|
| Original ten | 9 of 10 · 189 s · 26 calls | 9 of 10 · 161 s · 26 calls | 9 of 10 · 388 s · 77 calls |
| Harder seven | 5 of 7 · 159 s · 23 calls | 5 of 7 · 159 s · 21 calls | 4 of 7 · 541 s · 101 calls |

What this shows:

- **Speed and cost.** Against Ghost OS on the same seventeen tasks, the default profile took 63% less time, made 72% fewer tool calls and used 44% fewer tokens by Codex's count; the simple profile took 66% less time and used 57% fewer tokens. The gap is widest on the harder tasks (159 s against 541 s). Most of it is fewer model calls: with `pc_do` a Calculator sum or a form is one or two calls.
- **Reliability is not separated by this data.** 14 against 13 of 17 is one run, in one trial. The three stacks tied on the original ten with different failures, and YouxPC passed one more of the harder seven. That is not evidence that either is more reliable.
- **Pointer.** All 97 actions that report a delivery path in the two YouxPC arms (58 and 39) went through accessibility. None moved the pointer.

Every failure in the valid trial:

| Stack | Task | What happened |
|---|---|---|
| YouxPC default | `calc-chain` | Pressed keys by id and got them wrong: next to keys labelled 5 and 6, ids e5 and e6 belonged to the 7 and 8 keys. Calculator showed 114.5. YouxPC's fault in part; see below. |
| YouxPC simple | `calc-chain` | Entered 128 + 256 ÷ 4 with no equals in between; Calculator applied precedence and showed 192. The model reported 192. |
| YouxPC both | `web-long-form` | Opened the Team dropdown and sent `p`, `return` in the same `pc_do`. The keys went out before the menu was up, or the next step arrived before it had closed; the team was never set, every step reported ok, and the model said it was done. YouxPC's fault. |
| YouxPC default | `calc-long` | Typed the whole expression (precedence, wrong), then pressed Clear where All Clear was needed and typed onto the old expression. |
| YouxPC simple | `calc-long` | Precedence again: 461.67. The model reported it as the result. |
| Ghost OS | `web-checkbox-select` | Saved with the colour not chosen, and said it had chosen Blue. |
| Ghost OS | `web-long-form` | Left the pre-ticked "Share usage data" box ticked. |
| Ghost OS | `web-async-search` | Opened "Osprey ridge trail (closed)" first, then the right one. |
| Ghost OS | `calc-long` | Precedence, 461.67 on the display; it gave the right answer from its own arithmetic, which the strict rule does not count. |

Fixed after this pass, and not reflected in the numbers above:

- Dropdowns inside `pc_do`: a step that depends on keyboard focus now gets the full pause after the step before it, and after a menu item or a confirming key the next step waits until the menu has closed. Replaying the model's exact thirteen-step call from the failed `web-long-form` run then set all seven fields correctly, three times out of three.
- Ids and labels: a new id is never a number that is also a label on screen (Calculator's ids now start at e10), and using a label as an id fails with the right id in the message instead of pressing another key.

Neither fix could be re-measured with the model, because the quota does not return until 5 November 2026.

Caveats that belong with these numbers:

- One trial per task. No variance is known.
- I wrote the seven harder tasks and, before the run, drove each page with YouxPC by hand. That found and fixed six faults in YouxPC first (tables listed twice, ids that moved between rows, a name shared by several buttons acted on the first, checkbox and radio state missing, a restarted browser not found, a dropdown choice lost inside a sequence). Ghost OS got no such preparation. The harder set is therefore biased towards YouxPC, and the fair reading of 5 against 4 is "no difference shown".
- YouxPC was also tuned on the original ten over three earlier passes.
- The time and call counts do not depend on that tuning in the same way: they come from doing more per call, and they held on every task (the per-task table is in `results/codex-v3/strict-summary.md`).

The sections below describe the third pass (the original ten tasks, two trials, before `pc_do`).

## What was compared

The same model, the same harness and the same ten tasks, with only the tool stack changed.

- **Model and harness:** `gpt-6-luna` through the Codex CLI (`codex exec`), free ChatGPT plan.
- **Tool stacks:**
  - YouxPC, default (core) profile
  - YouxPC, five-tool simple profile
  - Ghost OS 2.2.1, the project YouxPC was forked from
  - Codex's own computer use
- **Tasks:** two in Calculator, one in TextEdit, seven on local web pages in Brave (click, form, checkbox and dropdown, read, scroll, dialog, three-step wizard). See `tasks.py`.
- **Scoring:** web tasks are judged by what the page itself recorded, the TextEdit task by the document's text, the read task by the answer. A Calculator run counts only if the Calculator display showed the result (`analyze.py`), because a model can do arithmetic without the app.
- **Runs:** two trials per task per stack, one at a time on one screen. 180 s hard limit per run (120 s for Calculator and TextEdit, 240 s for the wizard).

## Headline

| Tool stack | Tasks passed | Total time, 20 runs | Total tokens, 20 runs | Median tool calls |
|---|---|---|---|---|
| YouxPC, core profile | 19 of 20 | 472 s | 448,899 | 3.5 |
| YouxPC, simple profile | 18 of 20 | 529 s | 333,652 | 4 |
| Ghost OS 2.2.1 | 20 of 20 | 724 s | 566,470 | 6 |
| Codex's own computer use | not scored | | | |

- Ghost OS was the most reliable: it passed every run.
- YouxPC's core profile took 35% less time and 21% fewer tokens than Ghost OS, and failed one run.
- YouxPC's simple profile used 41% fewer tokens than Ghost OS and 27% less time, and failed two runs.
- Token totals are Codex's own "tokens used" figures and include its system prompt on every model call.
- In the YouxPC core runs, all 30 actions that report a delivery path went through accessibility: none moved the pointer.

## Per task

Each cell is passes, median seconds, median tokens over the two trials.

| Task | YouxPC core | YouxPC simple | Ghost OS 2.2.1 |
|---|---|---|---|
| `calc-chain` | 2/2 · 32 s · 20,410 | 0/2 · 40 s · 13,792 | 2/2 · 24 s · 21,530 |
| `calc-multiply` | 2/2 · 41 s · 18,102 | 2/2 · 46 s · 33,645 | 2/2 · 35 s · 31,466 |
| `textedit-type` | 2/2 · 19 s · 17,158 | 2/2 · 14 s · 15,988 | 2/2 · 16 s · 19,881 |
| `web-checkbox-select` | 1/2 · 29 s · 31,396 | 2/2 · 23 s · 14,463 | 2/2 · 46 s · 38,632 |
| `web-click` | 2/2 · 11 s · 19,221 | 2/2 · 27 s · 12,443 | 2/2 · 20 s · 17,958 |
| `web-dialog` | 2/2 · 21 s · 23,916 | 2/2 · 38 s · 18,803 | 2/2 · 39 s · 30,464 |
| `web-form` | 2/2 · 25 s · 22,006 | 2/2 · 20 s · 17,852 | 2/2 · 42 s · 25,318 |
| `web-read` | 2/2 · 9 s · 22,814 | 2/2 · 8 s · 8,444 | 2/2 · 20 s · 19,455 |
| `web-scroll` | 2/2 · 23 s · 19,841 | 2/2 · 18 s · 14,838 | 2/2 · 51 s · 42,690 |
| `web-wizard` | 2/2 · 26 s · 29,586 | 2/2 · 31 s · 16,557 | 2/2 · 68 s · 35,840 |

## The failures

- **YouxPC core, `web-checkbox-select`, one run.** The model ticked the checkbox, later re-read the page, saw no sign that it was ticked, clicked it again and saved it unticked. The listing did not show checkbox state because the browser only reports it in its fuller accessibility mode. Fixed after this run (state is now shown, and the mode is switched on). Re-test after the fix: 4 of 4.
- **YouxPC simple, `calc-chain`, both runs.** `pc_key` rejected the `+` key (it was parsed as a separator), so "128 + 256" became "128256". Fixed after this run. Re-test after the fix: 2 of 4. Both remaining failures were the model pressing 128 + 256 ÷ 4 without an equals in between; Calculator applied operator precedence and showed 192, which the model reported correctly.

## Small local models

Run through Ollama on the same M1. One trial per task, at most 15 model calls per run. Time limit per run: 90 s for Qwen3 1.7B, 150 s for MiniCPM5-2B, 180 s for the others. Thinking output is off where a model has it. Scoring is the strict rule used above: a Calculator run counts only if Calculator's display showed the result.

| Model and setup | Tasks passed | Which | Time, all 10 | Tokens, all 10 |
|---|---|---|---|---|
| Qwen3 4B instruct, core profile, native tool calling | 4 of 10 | checkbox and dropdown, read, scroll, dialog | 335 s | 141,016 |
| Qwen3 4B instruct, simple profile, native tool calling | 4 of 10 | type in TextEdit, form, read, scroll | 144 s | 37,589 |
| Qwen3 1.7B, core profile, native tool calling | 4 of 10 | type in TextEdit, click, read, scroll | 343 s | 104,328 |
| Qwen3 1.7B, simple profile, native tool calling | 2 of 10 | read, scroll | 331 s | 170,796 |
| Qwen3 1.7B, simple profile, text protocol | 2 of 10 | read, dialog | 110 s | 21,198 |
| Gemma 3n E2B, simple profile, text protocol | 2 of 10 | click, scroll | 305 s | 37,216 |
| Gemma 3n E2B, core profile, text protocol | 1 of 10 | read | 655 s | 76,878 |
| MiniCPM5-2B, simple profile, text protocol | 0 of 10 | | | |
| MiniCPM5-2B, core profile, text protocol | 0 of 10 | | | |

What this does and does not show:

- **No small model tested here can be relied on.** The best result is 4 of 10.
- **A 4B model gets through multi-step tasks that a 1.7B model does not.** Qwen3 4B filled and submitted the form, ticked a checkbox and chose from a dropdown and saved, and renamed an item through a dialog. Across its two profiles it passed six different tasks, though never more than four in one run of the suite. It never finished the three-step wizard.
- **It also reports things it did not do.** In the simple profile, three runs looked at the page once and then said the task was done. In both profiles it answered the two Calculator sums correctly but stopped pressing keys partway and gave the answer from its head; the checker's plain rule would count those (6 of 10 in each profile), the strict rule does not.
- **Two of its core-profile failures were YouxPC's fault.** On two of six identical first snapshots of a freshly opened browser, the page was missing and only the browser's toolbar was listed; the model then acted on the toolbar. And typing `into:"textarea"` failed although the snapshot showed exactly one unnamed text area. Both are fixed; see the re-test below. Whether the first problem also occurred in the runs with the large model was not checked; a stronger model would recover from it by taking a second snapshot, at a cost in time and tokens.
- **The simple profile is a mixed result, not a win.** For the 4B model it gave the same pass count in 43% of the time and 27% of the tokens. Gemma passed 2 against 1. The 1.7B model did worse with it (2 against 4).
- **A 1.7B model can do single-step tasks and not multi-step ones.** Its passes need one or two actions. On the form, dropdown, wizard and Calculator tasks it looped (46 tool calls in one run), invented element ids, or stopped early and claimed success.
- **MiniCPM5-2B was not fairly tested.** Ollama lists it without tool-calling support, so tools were described in the prompt and its replies parsed as text. It wrote calls in a format of its own (`<function name="pc_click"><param name="n">`), usually malformed, and almost none could be executed. A second pass after the parser change below gave 0 of 10 twice again (`results/local-models-minicpm-rerun`). Its model card describes tool calling through llama.cpp with a dedicated parser; that route was not tried. The zero is a result about this setup, not about the model.

Runs that are kept but not reported, and why:

- `results/local-models-first-attempt`: failed for harness reasons (a parameter Ollama rejected, no cap on reply length, tool calls written as text being treated as answers).
- `results/local-models-gemma3n-calls-rejected`: Gemma 3n scored 0 of 20 with no tool call executed. It was writing correct calls with typographic quotes and a spaced closing tag, and the harness's parser rejected every one. The parser now accepts both, and the Gemma rows above are from the run after that.
- `results/local-models-4b-thinking-aborted`: Ollama's default `qwen3:4b` tag is a thinking build. It took 45 to 70 s per model call on this machine; two runs were made, both failed, and the arm was stopped. The rows above use `qwen3:4b-instruct`.

Not run: Gemma 4 E2B. The installed Ollama (0.20.3) is too old to pull it.

Builds: the Qwen3 1.7B rows and the first MiniCPM pass used the build the headline table used. The other rows used a build one commit later (never-press list, a 3 s accessibility timeout, a cleared terminal start); none of those changes touch these tasks' paths except the timeout.

### Re-test after the two fixes (Qwen3 4B instruct, core profile)

The eight tasks outside Calculator, two trials each, same limits (`results/retest-4b-after-snapshot-fix`):

- 12 of 16 runs passed, which is 6 of the 8 tasks; at temperature 0 both trials of a task went the same way. Before the fixes the same model and profile passed 4 of these 8. `web-click` and `textedit-type` now pass.
- All 14 first snapshots of the browser contained the page, against 4 of 6 before. A first snapshot of a new browser takes about 1.1 s.
- The two tasks that still fail are the model stopping one step short. It filled the form and never pressed Submit, and it filled the wizard's last step and never pressed Finish, reporting success both times.

This is a re-test on tasks whose failures prompted the fixes. It shows the fixes work. It does not show how the model would do on tasks it has not been tuned against.

What was wrong: Chromium builds a page's accessibility tree only after a client reads the role of the application element, and the page then appears a moment later. YouxPC looked for the page once, straight away, and on a machine busy with a local model that was sometimes too early; it then never looked again for that browser. It now asks explicitly and waits up to two seconds.

## Codex's own computer use

Not scored. Every run ended within about 15 seconds with a message such as "computer use was not approved for Brave Browser". Codex asks the user to approve each app, and nobody was at the machine to do that. These runs say nothing about how well it works once approved.

## How these numbers were arrived at

This is the third pass over the same ten tasks, and YouxPC was changed between passes in response to what failed.

1. First pass, one trial: YouxPC core 9 of 10, simple 8 of 10, Ghost OS 10 of 10.
2. Second pass, two trials: YouxPC core 18 of 20, simple 18 of 20, Ghost OS 20 of 20. All four YouxPC failures were Calculator tasks. Three were the model confusing an element's number with its label: Calculator's keys are buttons named "7", "8", "9", and a line read `[7] button "9"`. Element ids were then changed to the form `e7`.
3. Third pass, two trials, YouxPC only: the numbers in the headline table. The Ghost OS figures are from the second pass; it was not changed and not re-run.

So YouxPC has been tuned on this suite and Ghost OS has not. The suite is small (ten tasks, three apps) and every task is short. Treat the reliability comparison as "both work on simple tasks, Ghost OS slightly better here", and the time and token comparison as the more robust finding: it held in every pass.

Raw logs for every run, including the earlier passes and the aborted one, are in `results/`.

## What was not measured

- **Claude models.** The headless Claude CLI could not authenticate from the session that ran the benchmark.
- **Other open-source tools** (Peekaboo, Cua, and others). Not installed; only Ghost OS was compared.
- **Long or hard tasks.** Nothing here takes more than about ten actions.
- **Native apps beyond Calculator and TextEdit.**
- **Variance.** Two trials per task is too few for confidence intervals, and the local models had one.

## What is published

For every pass, `results/<pass>/runs.jsonl` has one record per run (task, tool, pass or fail, the checker's note, time, tool calls, tokens, the model's final message) and `strict-summary.md` has the totals. For the YouxPC arms of the fifth and sixth passes, `results/<pass>/traces/` also has every tool call and its answer, with local paths removed; the project page replays three of them.

The raw output of the other tools is not in the repository. It runs to several hundred megabytes, because some of them return screenshots, and it carries session ids and local paths. Ask if you want it, or run the commands below.

## Reproduce

```bash
swift build
git clone --depth 1 --branch v2.2.1 https://github.com/ghostwright/ghost-os.git ../ghost-os && (cd ../ghost-os && swift build)
# Fifth pass: Claude through `claude -p` (seventeen tasks; `all` is the ten short ones, `hard` the other seven)
python3 bench/run.py --yes --trials 3 --tasks all+hard \
    --systems youxpc-haiku,youxpc-simple-haiku,ghostos-haiku \
    --ghostos-bin ../ghost-os/.build/debug/ghost --out bench/results/my-run
# Sixth pass: other tools (install them first; Cua Driver needs its own permissions granted)
#   --systems youxpc-haiku,peekaboo-haiku,peekaboo-fg-haiku,cua-haiku      on all+hard
#   --systems playwright-haiku                                             on the web tasks only
# Fourth pass: the same with the Codex CLI as the model
#   --systems codex-youxpc,codex-youxpc-simple,codex-ghostos
python3 bench/analyze.py bench/results/my-run/runs.jsonl
```

The run drives the real desktop, opens Brave with a throwaway profile, and needs Accessibility and Screen Recording granted to the app that launches it.
