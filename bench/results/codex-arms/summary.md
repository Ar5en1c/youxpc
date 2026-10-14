# Benchmark summary

Valid runs: 40. Infrastructure failures excluded: 0. n/a means the system did not expose that number; nothing is estimated.

## Per system

| System | Success | Wall s median (successful) | Wall s median (all runs) | Wall s mean (all runs) | Total tokens median (successful) | Total tokens median (all runs) | Tool calls median (successful) | Tool calls median (all runs) | Total cost USD | Timeouts |
|---|---|---|---|---|---|---|---|---|---|---|
| codex-youxpc | 10/10 (100%) | 18.8 | 18.8 | 20.3 | 18,437 (n=10) | 18,437 (n=10) | 3.5 (n=10) | 3.5 (n=10) | n/a | 0 |
| codex-youxpc-simple | 8/10 (80%) | 19.8 | 21.4 | 37.8 | 18,090 (n=8) | 18,970 (n=10) | 4.0 (n=8) | 4.0 (n=10) | n/a | 0 |
| codex-ghostos | 10/10 (100%) | 28.2 | 28.2 | 37.0 | 29,778 (n=10) | 29,778 (n=10) | 5.0 (n=10) | 5.0 (n=10) | n/a | 0 |
| codex | 2/10 (20%) | 10.8 | 11.7 | 12.0 | 22,175 (n=2) | 22,108 (n=10) | n/a (n=0) | n/a (n=0) | n/a | 0 |

Medians are labelled by population: *successful* = runs where the checker passed, *all runs* = every valid run including failures and timeouts. (n=k) is the number of runs that reported that metric.

## Pointer paths (YouxPC systems)

- codex-youxpc: virtual 14, system-returned 0, system 0 (parsed from 10 runs)
- codex-youxpc-simple: virtual 0, system-returned 0, system 0 (parsed from 10 runs)

## Desktop evidence (Calculator / TextEdit read-back)

- codex-youxpc: 2/3 runs show the expected text on screen
- codex-youxpc-simple: 2/3 runs show the expected text on screen
- codex-ghostos: 3/3 runs show the expected text on screen
- codex: 0/3 runs show the expected text on screen

Success for calculator tasks follows the final answer (as specified); this line is the independent on-screen check.

## Per task (successes/trials, median wall seconds over all runs)

| Task | codex-youxpc | codex-youxpc-simple | codex-ghostos | codex |
|---|---|---|---|---|
| calc-multiply | 1/1 · 22.3s | 1/1 · 91.1s | 1/1 · 40.3s | 1/1 · 9.9s |
| calc-chain | 1/1 · 14.0s | 1/1 · 67.4s | 1/1 · 23.6s | 1/1 · 11.6s |
| textedit-type | 1/1 · 11.4s | 0/1 · 22.8s | 1/1 · 20.4s | 0/1 · 8.9s |
| web-click | 1/1 · 15.3s | 1/1 · 11.5s | 1/1 · 18.6s | 0/1 · 14.0s |
| web-form | 1/1 · 22.3s | 1/1 · 20.0s | 1/1 · 29.9s | 0/1 · 12.5s |
| web-checkbox-select | 1/1 · 35.8s | 0/1 · 83.3s | 1/1 · 49.2s | 0/1 · 11.8s |
| web-read | 1/1 · 9.2s | 1/1 · 10.7s | 1/1 · 13.7s | 0/1 · 10.3s |
| web-scroll | 1/1 · 15.0s | 1/1 · 19.6s | 1/1 · 27.9s | 0/1 · 12.2s |
| web-dialog | 1/1 · 23.1s | 1/1 · 17.5s | 1/1 · 28.4s | 0/1 · 19.2s |
| web-wizard | 1/1 · 34.3s | 1/1 · 34.6s | 1/1 · 118.3s | 0/1 · 9.5s |
