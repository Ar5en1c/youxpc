# Benchmark summary

Valid runs: 8. Infrastructure failures excluded: 0. n/a means the system did not expose that number; nothing is estimated.

## Per system

| System | Success | Wall s median (successful) | Wall s median (all runs) | Wall s mean (all runs) | Total tokens median (successful) | Total tokens median (all runs) | Tool calls median (successful) | Tool calls median (all runs) | Total cost USD | Timeouts |
|---|---|---|---|---|---|---|---|---|---|---|
| codex-youxpc | 3/4 (75%) | 21.4 | 22.1 | 39.6 | 22,550 (n=3) | 20,892 (n=4) | 5.0 (n=3) | 5.5 (n=4) | n/a | 0 |
| codex-youxpc-simple | 3/4 (75%) | 24.2 | 21.0 | 21.7 | 16,953 (n=3) | 17,643 (n=4) | 5.0 (n=3) | 3.5 (n=4) | n/a | 0 |

Medians are labelled by population: *successful* = runs where the checker passed, *all runs* = every valid run including failures and timeouts. (n=k) is the number of runs that reported that metric.

## Pointer paths (YouxPC systems)

- codex-youxpc: virtual 28, system-returned 0, system 0 (parsed from 4 runs)
- codex-youxpc-simple: virtual 0, system-returned 0, system 0 (parsed from 4 runs)

## Desktop evidence (Calculator / TextEdit read-back)

- codex-youxpc: 1/2 runs show the expected text on screen
- codex-youxpc-simple: 1/2 runs show the expected text on screen

Success for calculator tasks follows the final answer (as specified); this line is the independent on-screen check.

## Per task (successes/trials, median wall seconds over all runs)

| Task | codex-youxpc | codex-youxpc-simple |
|---|---|---|
| calc-chain | 1/2 · 57.0s | 1/2 · 16.6s |
| web-checkbox-select | 2/2 · 22.1s | 2/2 · 26.8s |
