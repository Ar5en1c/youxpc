# Benchmark summary

Valid runs: 20. Infrastructure failures excluded: 0. n/a means the system did not expose that number; nothing is estimated.

## Per system

| System | Success | Wall s median (successful) | Wall s median (all runs) | Wall s mean (all runs) | Total tokens median (successful) | Total tokens median (all runs) | Tool calls median (successful) | Tool calls median (all runs) | Total cost USD | Timeouts |
|---|---|---|---|---|---|---|---|---|---|---|
| youxpc-ollama:qwen3:4b-instruct | 6/10 (60%) | 30.2 | 30.2 | 33.5 | 12,288 (n=6) | 12,288 (n=10) | 3.5 (n=6) | 3.5 (n=10) | n/a | 0 |
| youxpc-simple-ollama:qwen3:4b-instruct | 6/10 (60%) | 17.3 | 14.3 | 14.4 | 5,108 (n=6) | 3,459 (n=10) | 3.0 (n=6) | 2.0 (n=10) | n/a | 0 |

Medians are labelled by population: *successful* = runs where the checker passed, *all runs* = every valid run including failures and timeouts. (n=k) is the number of runs that reported that metric.

## Pointer paths (YouxPC systems)

- youxpc-ollama:qwen3:4b-instruct: virtual 15, system-returned 0, system 0 (parsed from 10 runs)
- youxpc-simple-ollama:qwen3:4b-instruct: virtual 0, system-returned 0, system 0 (parsed from 10 runs)

## Desktop evidence (Calculator / TextEdit read-back)

- youxpc-ollama:qwen3:4b-instruct: 0/3 runs show the expected text on screen
- youxpc-simple-ollama:qwen3:4b-instruct: 1/3 runs show the expected text on screen

Success for calculator tasks follows the final answer (as specified); this line is the independent on-screen check.

## Per task (successes/trials, median wall seconds over all runs)

| Task | youxpc-ollama:qwen3:4b-instruct | youxpc-simple-ollama:qwen3:4b-instruct |
|---|---|---|
| calc-multiply | 1/1 · 28.9s | 1/1 · 17.9s |
| calc-chain | 1/1 · 26.2s | 1/1 · 18.5s |
| textedit-type | 0/1 · 27.5s | 1/1 · 12.0s |
| web-click | 0/1 · 23.0s | 0/1 · 7.4s |
| web-form | 0/1 · 52.7s | 1/1 · 16.6s |
| web-checkbox-select | 1/1 · 39.9s | 0/1 · 7.8s |
| web-read | 1/1 · 22.9s | 1/1 · 7.7s |
| web-scroll | 1/1 · 38.4s | 1/1 · 25.3s |
| web-dialog | 1/1 · 31.5s | 0/1 · 7.3s |
| web-wizard | 0/1 · 43.9s | 0/1 · 23.4s |
