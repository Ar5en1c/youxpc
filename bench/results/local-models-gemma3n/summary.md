# Benchmark summary

Valid runs: 20. Infrastructure failures excluded: 0. n/a means the system did not expose that number; nothing is estimated.

## Per system

| System | Success | Wall s median (successful) | Wall s median (all runs) | Wall s mean (all runs) | Total tokens median (successful) | Total tokens median (all runs) | Tool calls median (successful) | Tool calls median (all runs) | Total cost USD | Timeouts |
|---|---|---|---|---|---|---|---|---|---|---|
| youxpc-text-ollama:gemma3n:e2b | 1/10 (10%) | 24.5 | 51.8 | 65.5 | 3,275 (n=1) | 7,249 (n=10) | 1.0 (n=1) | 1.0 (n=10) | n/a | 0 |
| youxpc-simple-text-ollama:gemma3n:e2b | 2/10 (20%) | 31.7 | 33.5 | 30.5 | 4,923 (n=2) | 3,733 (n=10) | 2.0 (n=2) | 2.0 (n=10) | n/a | 0 |

Medians are labelled by population: *successful* = runs where the checker passed, *all runs* = every valid run including failures and timeouts. (n=k) is the number of runs that reported that metric.

## Pointer paths (YouxPC systems)

- youxpc-text-ollama:gemma3n:e2b: virtual 0, system-returned 4, system 0 (parsed from 10 runs)
- youxpc-simple-text-ollama:gemma3n:e2b: virtual 0, system-returned 0, system 0 (parsed from 10 runs)

## Desktop evidence (Calculator / TextEdit read-back)

- youxpc-text-ollama:gemma3n:e2b: 0/3 runs show the expected text on screen
- youxpc-simple-text-ollama:gemma3n:e2b: 0/3 runs show the expected text on screen

Success for calculator tasks follows the final answer (as specified); this line is the independent on-screen check.

## Per task (successes/trials, median wall seconds over all runs)

| Task | youxpc-text-ollama:gemma3n:e2b | youxpc-simple-text-ollama:gemma3n:e2b |
|---|---|---|
| calc-multiply | 0/1 · 23.0s | 0/1 · 34.2s |
| calc-chain | 0/1 · 26.0s | 0/1 · 34.4s |
| textedit-type | 0/1 · 82.5s | 0/1 · 33.9s |
| web-click | 0/1 · 60.9s | 1/1 · 21.5s |
| web-form | 0/1 · 42.7s | 0/1 · 9.5s |
| web-checkbox-select | 0/1 · 158.6s | 0/1 · 22.5s |
| web-read | 1/1 · 24.5s | 0/1 · 33.0s |
| web-scroll | 0/1 · 27.2s | 1/1 · 41.9s |
| web-dialog | 0/1 · 67.2s | 0/1 · 32.4s |
| web-wizard | 0/1 · 142.0s | 0/1 · 41.5s |
