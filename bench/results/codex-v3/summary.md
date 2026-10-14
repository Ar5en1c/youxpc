# Benchmark summary

Valid runs: 56. Infrastructure failures excluded: 46. n/a means the system did not expose that number; nothing is estimated.

## Per system

| System | Success | Wall s median (successful) | Wall s median (all runs) | Wall s mean (all runs) | Total tokens median (successful) | Total tokens median (all runs) | Tool calls median (successful) | Tool calls median (all runs) | Total cost USD | Timeouts |
|---|---|---|---|---|---|---|---|---|---|---|
| codex-youxpc | 15/19 (79%) | 18.1 | 19.7 | 20.0 | 18,741 (n=15) | 18,741 (n=19) | 3.0 (n=15) | 3.0 (n=19) | n/a | 0 |
| codex-youxpc-simple | 15/19 (79%) | 19.5 | 19.5 | 18.7 | 15,077 (n=15) | 14,241 (n=19) | 3.0 (n=15) | 2.0 (n=19) | n/a | 0 |
| codex-ghostos | 15/18 (83%) | 44.3 | 44.6 | 52.8 | 28,798 (n=15) | 32,962 (n=18) | 8.0 (n=15) | 9.5 (n=18) | n/a | 0 |

Medians are labelled by population: *successful* = runs where the checker passed, *all runs* = every valid run including failures and timeouts. (n=k) is the number of runs that reported that metric.

## Pointer paths (YouxPC systems)

- codex-youxpc: virtual 73, system-returned 0, system 0 (parsed from 19 runs)
- codex-youxpc-simple: virtual 56, system-returned 0, system 0 (parsed from 19 runs)

## Desktop evidence (Calculator / TextEdit read-back)

- codex-youxpc: 3/6 runs show the expected text on screen
- codex-youxpc-simple: 3/6 runs show the expected text on screen
- codex-ghostos: 4/5 runs show the expected text on screen

Success for calculator tasks follows the final answer (as specified); this line is the independent on-screen check.

## Per task (successes/trials, median wall seconds over all runs)

| Task | codex-youxpc | codex-youxpc-simple | codex-ghostos |
|---|---|---|---|
| calc-multiply | 2/2 · 15.3s | 2/2 · 15.4s | 2/2 · 33.4s |
| calc-chain | 0/2 · 19.6s | 0/2 · 16.4s | 1/1 · 25.1s |
| textedit-type | 1/1 · 9.1s | 1/1 · 12.8s | 1/1 · 15.5s |
| web-click | 1/1 · 14.8s | 1/1 · 9.9s | 1/1 · 30.7s |
| web-form | 1/1 · 17.3s | 1/1 · 19.4s | 1/1 · 55.2s |
| web-checkbox-select | 1/1 · 37.0s | 1/1 · 23.9s | 0/1 · 48.3s |
| web-read | 1/1 · 8.2s | 1/1 · 10.0s | 1/1 · 28.1s |
| web-scroll | 1/1 · 18.1s | 1/1 · 21.3s | 1/1 · 45.0s |
| web-dialog | 1/1 · 22.2s | 1/1 · 16.8s | 1/1 · 42.6s |
| web-wizard | 1/1 · 25.1s | 1/1 · 19.5s | 1/1 · 52.9s |
| web-rows | 1/1 · 16.6s | 1/1 · 21.3s | 1/1 · 57.1s |
| web-long-form | 0/1 · 23.3s | 0/1 · 25.3s | 0/1 · 201.7s |
| web-confirm-delete | 1/1 · 20.8s | 1/1 · 23.3s | 1/1 · 47.5s |
| web-tabs | 1/1 · 30.6s | 1/1 · 21.5s | 1/1 · 99.4s |
| web-async-search | 1/1 · 23.4s | 1/1 · 25.0s | 0/1 · 43.1s |
| web-reveal-enter | 1/1 · 19.7s | 1/1 · 21.3s | 1/1 · 48.1s |
| calc-long | 0/1 · 24.8s | 0/1 · 20.9s | 1/1 · 44.0s |

## Infrastructure failures (excluded)

- codex-ghostos calc-chain t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc textedit-type t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc-simple textedit-type t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-ghostos textedit-type t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc web-click t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc-simple web-click t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-ghostos web-click t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc web-form t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc-simple web-form t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-ghostos web-form t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc web-checkbox-select t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc-simple web-checkbox-select t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-ghostos web-checkbox-select t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc web-read t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc-simple web-read t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-ghostos web-read t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc web-scroll t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc-simple web-scroll t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-ghostos web-scroll t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc web-dialog t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc-simple web-dialog t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-ghostos web-dialog t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc web-wizard t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc-simple web-wizard t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-ghostos web-wizard t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc web-rows t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc-simple web-rows t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-ghostos web-rows t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc web-long-form t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc-simple web-long-form t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-ghostos web-long-form t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc web-confirm-delete t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc-simple web-confirm-delete t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-ghostos web-confirm-delete t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc web-tabs t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc-simple web-tabs t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-ghostos web-tabs t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc web-async-search t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc-simple web-async-search t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-ghostos web-async-search t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc web-reveal-enter t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc-simple web-reveal-enter t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-ghostos web-reveal-enter t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc calc-long t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-youxpc-simple calc-long t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
- codex-ghostos calc-long t2: codex exit 1: s://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}
{"type":"turn.failed","error":{"message":"You’ve hit your usage limit. Upgrade to Plus to continue using Codex (https://chatgpt.com/explore/plus), or try again at Nov 5th, 2026 7:27 PM."}}

Reading additional input from stdin...
