# Benchmark summary

Valid runs: 16. Infrastructure failures excluded: 0. n/a means the system did not expose that number; nothing is estimated.

## Per system

| System | Success | Wall s median (successful) | Wall s median (all runs) | Wall s mean (all runs) | Total tokens median (successful) | Total tokens median (all runs) | Tool calls median (successful) | Tool calls median (all runs) | Total cost USD | Timeouts |
|---|---|---|---|---|---|---|---|---|---|---|
| youxpc-ollama:qwen3:4b-instruct | 12/16 (75%) | 14.7 | 17.7 | 17.8 | 11,072 (n=12) | 12,606 (n=16) | 2.5 (n=12) | 3.0 (n=16) | n/a | 0 |

Medians are labelled by population: *successful* = runs where the checker passed, *all runs* = every valid run including failures and timeouts. (n=k) is the number of runs that reported that metric.

## Pointer paths (YouxPC systems)

- youxpc-ollama:qwen3:4b-instruct: virtual 20, system-returned 0, system 0 (parsed from 16 runs)

## Desktop evidence (Calculator / TextEdit read-back)

- youxpc-ollama:qwen3:4b-instruct: 2/2 runs show the expected text on screen

Success for calculator tasks follows the final answer (as specified); this line is the independent on-screen check.

## Per task (successes/trials, median wall seconds over all runs)

| Task | youxpc-ollama:qwen3:4b-instruct |
|---|---|
| web-click | 2/2 · 10.5s |
| web-form | 0/2 · 16.6s |
| web-wizard | 0/2 · 31.3s |
| web-read | 2/2 · 9.3s |
| web-scroll | 2/2 · 23.5s |
| web-dialog | 2/2 · 18.8s |
| web-checkbox-select | 2/2 · 24.3s |
| textedit-type | 2/2 · 7.9s |
