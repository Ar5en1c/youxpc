# Benchmark summary

Valid runs: 20. Infrastructure failures excluded: 0. n/a means the system did not expose that number; nothing is estimated.

## Per system

| System | Success | Wall s median (successful) | Wall s median (all runs) | Wall s mean (all runs) | Total tokens median (successful) | Total tokens median (all runs) | Tool calls median (successful) | Tool calls median (all runs) | Total cost USD | Timeouts |
|---|---|---|---|---|---|---|---|---|---|---|
| youxpc-text-ollama:openbmb/minicpm5-2b:latest | 0/10 (0%) | n/a | 14.8 | 14.4 | n/a (n=0) | 5,804 (n=10) | n/a (n=0) | 0.0 (n=10) | n/a | 0 |
| youxpc-simple-text-ollama:openbmb/minicpm5-2b:latest | 0/10 (0%) | n/a | 18.3 | 22.4 | n/a (n=0) | 2,836 (n=10) | n/a (n=0) | 0.0 (n=10) | n/a | 0 |

Medians are labelled by population: *successful* = runs where the checker passed, *all runs* = every valid run including failures and timeouts. (n=k) is the number of runs that reported that metric.

## Pointer paths (YouxPC systems)

- youxpc-text-ollama:openbmb/minicpm5-2b:latest: virtual 0, system-returned 0, system 0 (parsed from 10 runs)
- youxpc-simple-text-ollama:openbmb/minicpm5-2b:latest: virtual 0, system-returned 0, system 0 (parsed from 10 runs)

## Desktop evidence (Calculator / TextEdit read-back)

- youxpc-text-ollama:openbmb/minicpm5-2b:latest: 0/3 runs show the expected text on screen
- youxpc-simple-text-ollama:openbmb/minicpm5-2b:latest: 0/3 runs show the expected text on screen

Success for calculator tasks follows the final answer (as specified); this line is the independent on-screen check.

## Per task (successes/trials, median wall seconds over all runs)

| Task | youxpc-text-ollama:openbmb/minicpm5-2b:latest | youxpc-simple-text-ollama:openbmb/minicpm5-2b:latest |
|---|---|---|
| calc-multiply | 0/1 · 13.4s | 0/1 · 24.2s |
| calc-chain | 0/1 · 14.6s | 0/1 · 43.2s |
| textedit-type | 0/1 · 16.7s | 0/1 · 10.7s |
| web-click | 0/1 · 15.7s | 0/1 · 31.5s |
| web-form | 0/1 · 15.2s | 0/1 · 16.2s |
| web-checkbox-select | 0/1 · 15.1s | 0/1 · 11.1s |
| web-read | 0/1 · 12.2s | 0/1 · 20.4s |
| web-scroll | 0/1 · 13.1s | 0/1 · 42.7s |
| web-dialog | 0/1 · 15.0s | 0/1 · 10.3s |
| web-wizard | 0/1 · 12.6s | 0/1 · 13.5s |
