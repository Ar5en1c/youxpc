# Benchmark summary

Valid runs: 9. Infrastructure failures excluded: 0. n/a means the system did not expose that number; nothing is estimated.

## Per system

| System | Success | Wall s median (successful) | Wall s median (all runs) | Wall s mean (all runs) | Total tokens median (successful) | Total tokens median (all runs) | Tool calls median (successful) | Tool calls median (all runs) | Total cost USD | Timeouts |
|---|---|---|---|---|---|---|---|---|---|---|
| codex-youxpc | 3/3 (100%) | 11.6 | 11.6 | 12.3 | 15,556 (n=3) | 15,556 (n=3) | 3.0 (n=3) | 3.0 (n=3) | n/a | 0 |
| codex-youxpc-simple | 2/3 (67%) | 22.3 | 29.4 | 24.7 | 19,228 (n=2) | 24,334 (n=3) | 4.5 (n=2) | 7.0 (n=3) | n/a | 0 |
| codex-ghostos | 3/3 (100%) | 29.5 | 29.5 | 29.2 | 26,280 (n=3) | 26,280 (n=3) | 6.0 (n=3) | 6.0 (n=3) | n/a | 0 |

Medians are labelled by population: *successful* = runs where the checker passed, *all runs* = every valid run including failures and timeouts. (n=k) is the number of runs that reported that metric.

## Pointer paths (YouxPC systems)

- codex-youxpc: virtual 0, system-returned 0, system 0 (parsed from 3 runs)
- codex-youxpc-simple: virtual 0, system-returned 0, system 0 (parsed from 3 runs)

## Desktop evidence (Calculator / TextEdit read-back)

- codex-youxpc: 3/3 runs show the expected text on screen
- codex-youxpc-simple: 1/3 runs show the expected text on screen
- codex-ghostos: 3/3 runs show the expected text on screen

Success for calculator tasks follows the final answer (as specified); this line is the independent on-screen check.

## Per task (successes/trials, median wall seconds over all runs)

| Task | codex-youxpc | codex-youxpc-simple | codex-ghostos |
|---|---|---|---|
| calc-multiply | 1/1 · 11.6s | 0/1 · 29.4s | 1/1 · 29.5s |
| calc-chain | 1/1 · 14.5s | 1/1 · 32.6s | 1/1 · 44.8s |
| textedit-type | 1/1 · 10.9s | 1/1 · 12.0s | 1/1 · 13.4s |
