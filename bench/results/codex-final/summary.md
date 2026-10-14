# Benchmark summary

Valid runs: 60. Infrastructure failures excluded: 0. n/a means the system did not expose that number; nothing is estimated.

## Per system

| System | Success | Wall s median (successful) | Wall s median (all runs) | Wall s mean (all runs) | Total tokens median (successful) | Total tokens median (all runs) | Tool calls median (successful) | Tool calls median (all runs) | Total cost USD | Timeouts |
|---|---|---|---|---|---|---|---|---|---|---|
| codex-youxpc | 18/20 (90%) | 19.5 | 22.2 | 27.2 | 19,554 (n=18) | 19,318 (n=19) | 3.5 (n=18) | 4.0 (n=20) | n/a | 1 |
| codex-youxpc-simple | 19/20 (95%) | 16.0 | 17.6 | 20.9 | 14,659 (n=19) | 14,545 (n=20) | 4.0 (n=19) | 4.0 (n=20) | n/a | 0 |
| codex-ghostos | 20/20 (100%) | 35.0 | 35.0 | 36.2 | 26,120 (n=20) | 26,120 (n=20) | 6.0 (n=20) | 6.0 (n=20) | n/a | 0 |

Medians are labelled by population: *successful* = runs where the checker passed, *all runs* = every valid run including failures and timeouts. (n=k) is the number of runs that reported that metric.

## Pointer paths (YouxPC systems)

- codex-youxpc: virtual 72, system-returned 0, system 0 (parsed from 20 runs)
- codex-youxpc-simple: virtual 0, system-returned 0, system 0 (parsed from 20 runs)

## Desktop evidence (Calculator / TextEdit read-back)

- codex-youxpc: 4/6 runs show the expected text on screen
- codex-youxpc-simple: 4/6 runs show the expected text on screen
- codex-ghostos: 6/6 runs show the expected text on screen

Success for calculator tasks follows the final answer (as specified); this line is the independent on-screen check.

## Per task (successes/trials, median wall seconds over all runs)

| Task | codex-youxpc | codex-youxpc-simple | codex-ghostos |
|---|---|---|---|
| calc-multiply | 1/2 · 38.0s | 2/2 · 28.5s | 2/2 · 35.0s |
| calc-chain | 1/2 · 68.5s | 1/2 · 36.3s | 2/2 · 23.6s |
| textedit-type | 2/2 · 11.2s | 2/2 · 15.5s | 2/2 · 16.3s |
| web-click | 2/2 · 11.3s | 2/2 · 11.0s | 2/2 · 19.8s |
| web-form | 2/2 · 29.9s | 2/2 · 20.4s | 2/2 · 42.4s |
| web-checkbox-select | 2/2 · 28.4s | 2/2 · 25.0s | 2/2 · 46.1s |
| web-read | 2/2 · 7.1s | 2/2 · 8.3s | 2/2 · 19.9s |
| web-scroll | 2/2 · 19.5s | 2/2 · 12.8s | 2/2 · 51.5s |
| web-dialog | 2/2 · 24.7s | 2/2 · 17.6s | 2/2 · 39.4s |
| web-wizard | 2/2 · 33.5s | 2/2 · 33.5s | 2/2 · 67.9s |
