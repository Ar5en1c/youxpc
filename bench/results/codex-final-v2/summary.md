# Benchmark summary

Valid runs: 40. Infrastructure failures excluded: 0. n/a means the system did not expose that number; nothing is estimated.

## Per system

| System | Success | Wall s median (successful) | Wall s median (all runs) | Wall s mean (all runs) | Total tokens median (successful) | Total tokens median (all runs) | Tool calls median (successful) | Tool calls median (all runs) | Total cost USD | Timeouts |
|---|---|---|---|---|---|---|---|---|---|---|
| codex-youxpc | 19/20 (95%) | 22.2 | 22.6 | 23.6 | 20,660 (n=19) | 21,196 (n=20) | 3.0 (n=19) | 3.5 (n=20) | n/a | 0 |
| codex-youxpc-simple | 20/20 (100%) | 21.3 | 21.3 | 26.5 | 16,312 (n=20) | 16,312 (n=20) | 4.0 (n=20) | 4.0 (n=20) | n/a | 0 |

Medians are labelled by population: *successful* = runs where the checker passed, *all runs* = every valid run including failures and timeouts. (n=k) is the number of runs that reported that metric.

## Pointer paths (YouxPC systems)

- codex-youxpc: virtual 30, system-returned 0, system 0 (parsed from 20 runs)
- codex-youxpc-simple: virtual 0, system-returned 0, system 0 (parsed from 20 runs)

## Desktop evidence (Calculator / TextEdit read-back)

- codex-youxpc: 6/6 runs show the expected text on screen
- codex-youxpc-simple: 4/6 runs show the expected text on screen

Success for calculator tasks follows the final answer (as specified); this line is the independent on-screen check.

## Per task (successes/trials, median wall seconds over all runs)

| Task | codex-youxpc | codex-youxpc-simple |
|---|---|---|
| calc-multiply | 2/2 · 40.9s | 2/2 · 45.8s |
| calc-chain | 2/2 · 32.1s | 2/2 · 40.1s |
| textedit-type | 2/2 · 19.3s | 2/2 · 14.4s |
| web-click | 2/2 · 11.0s | 2/2 · 27.1s |
| web-form | 2/2 · 24.6s | 2/2 · 19.7s |
| web-checkbox-select | 1/2 · 28.9s | 2/2 · 22.6s |
| web-read | 2/2 · 8.6s | 2/2 · 8.4s |
| web-scroll | 2/2 · 23.4s | 2/2 · 17.8s |
| web-dialog | 2/2 · 21.4s | 2/2 · 37.6s |
| web-wizard | 2/2 · 25.9s | 2/2 · 31.2s |
