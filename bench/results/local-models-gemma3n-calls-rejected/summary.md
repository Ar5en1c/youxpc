# Benchmark summary

Valid runs: 20. Infrastructure failures excluded: 0. n/a means the system did not expose that number; nothing is estimated.

## Per system

| System | Success | Wall s median (successful) | Wall s median (all runs) | Wall s mean (all runs) | Total tokens median (successful) | Total tokens median (all runs) | Tool calls median (successful) | Tool calls median (all runs) | Total cost USD | Timeouts |
|---|---|---|---|---|---|---|---|---|---|---|
| youxpc-text-ollama:gemma3n:e2b | 0/10 (0%) | n/a | 55.0 | 57.7 | n/a (n=0) | 6,084 (n=10) | n/a (n=0) | 0.0 (n=10) | n/a | 0 |
| youxpc-simple-text-ollama:gemma3n:e2b | 0/10 (0%) | n/a | 23.5 | 22.6 | n/a (n=0) | 2,558 (n=10) | n/a (n=0) | 0.0 (n=10) | n/a | 0 |

Medians are labelled by population: *successful* = runs where the checker passed, *all runs* = every valid run including failures and timeouts. (n=k) is the number of runs that reported that metric.

## Pointer paths (YouxPC systems)

- youxpc-text-ollama:gemma3n:e2b: virtual 0, system-returned 0, system 0 (parsed from 10 runs)
- youxpc-simple-text-ollama:gemma3n:e2b: virtual 0, system-returned 0, system 0 (parsed from 10 runs)

## Desktop evidence (Calculator / TextEdit read-back)

- youxpc-text-ollama:gemma3n:e2b: 0/3 runs show the expected text on screen
- youxpc-simple-text-ollama:gemma3n:e2b: 0/3 runs show the expected text on screen

Success for calculator tasks follows the final answer (as specified); this line is the independent on-screen check.

## Per task (successes/trials, median wall seconds over all runs)

| Task | youxpc-text-ollama:gemma3n:e2b | youxpc-simple-text-ollama:gemma3n:e2b |
|---|---|---|
| calc-multiply | 0/1 · 60.8s | 0/1 · 23.1s |
| calc-chain | 0/1 · 54.6s | 0/1 · 23.9s |
| textedit-type | 0/1 · 57.8s | 0/1 · 24.6s |
| web-click | 0/1 · 46.7s | 0/1 · 18.1s |
| web-form | 0/1 · 49.5s | 0/1 · 26.0s |
| web-checkbox-select | 0/1 · 52.3s | 0/1 · 25.6s |
| web-read | 0/1 · 55.4s | 0/1 · 23.2s |
| web-scroll | 0/1 · 59.2s | 0/1 · 26.4s |
| web-dialog | 0/1 · 88.0s | 0/1 · 14.4s |
| web-wizard | 0/1 · 52.8s | 0/1 · 20.9s |
