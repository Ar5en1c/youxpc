# Benchmark summary

Valid runs: 2. Infrastructure failures excluded: 0. n/a means the system did not expose that number; nothing is estimated.

## Per system

| System | Success | Wall s median (successful) | Wall s median (all runs) | Wall s mean (all runs) | Total tokens median (successful) | Total tokens median (all runs) | Tool calls median (successful) | Tool calls median (all runs) | Total cost USD | Timeouts |
|---|---|---|---|---|---|---|---|---|---|---|
| youxpc-ollama:qwen3:4b | 0/1 (0%) | n/a | 180.0 | 180.0 | n/a (n=0) | 6,876 (n=1) | n/a (n=0) | 1.0 (n=1) | n/a | 0 |
| youxpc-simple-ollama:qwen3:4b | 0/1 (0%) | n/a | 135.2 | 135.2 | n/a (n=0) | 6,019 (n=1) | n/a (n=0) | 1.0 (n=1) | n/a | 0 |

Medians are labelled by population: *successful* = runs where the checker passed, *all runs* = every valid run including failures and timeouts. (n=k) is the number of runs that reported that metric.

## Pointer paths (YouxPC systems)

- youxpc-ollama:qwen3:4b: virtual 0, system-returned 0, system 0 (parsed from 1 runs)
- youxpc-simple-ollama:qwen3:4b: virtual 0, system-returned 0, system 0 (parsed from 1 runs)

## Desktop evidence (Calculator / TextEdit read-back)

- youxpc-ollama:qwen3:4b: 0/1 runs show the expected text on screen
- youxpc-simple-ollama:qwen3:4b: 0/1 runs show the expected text on screen

Success for calculator tasks follows the final answer (as specified); this line is the independent on-screen check.

## Per task (successes/trials, median wall seconds over all runs)

| Task | youxpc-ollama:qwen3:4b | youxpc-simple-ollama:qwen3:4b |
|---|---|---|
| calc-multiply | 0/1 · 180.0s | 0/1 · 135.2s |
