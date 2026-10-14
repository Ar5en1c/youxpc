# Benchmark summary

Valid runs: 30. Infrastructure failures excluded: 0. n/a means the system did not expose that number; nothing is estimated.

## Per system

| System | Success | Wall s median (successful) | Wall s median (all runs) | Wall s mean (all runs) | Total tokens median (successful) | Total tokens median (all runs) | Tool calls median (successful) | Tool calls median (all runs) | Total cost USD | Timeouts |
|---|---|---|---|---|---|---|---|---|---|---|
| youxpc-simple-ollama:qwen3:1.7b | 0/10 (0%) | n/a | 16.8 | 29.8 | n/a (n=0) | 3,369 (n=8) | n/a (n=0) | 5.0 (n=10) | n/a | 0 |
| youxpc-ollama:qwen3:1.7b | 5/10 (50%) | 8.7 | 15.0 | 34.4 | 4,865 (n=5) | 5,352 (n=8) | 1.0 (n=5) | 1.5 (n=10) | n/a | 0 |
| youxpc-simple-text-ollama:openbmb/minicpm5-2b:latest | 0/10 (0%) | n/a | 0.1 | 0.1 | n/a (n=0) | n/a (n=0) | n/a (n=0) | 0.0 (n=10) | n/a | 0 |

Medians are labelled by population: *successful* = runs where the checker passed, *all runs* = every valid run including failures and timeouts. (n=k) is the number of runs that reported that metric.

## Pointer paths (YouxPC systems)

- youxpc-simple-ollama:qwen3:1.7b: virtual 0, system-returned 0, system 0 (parsed from 10 runs)
- youxpc-ollama:qwen3:1.7b: virtual 6, system-returned 0, system 0 (parsed from 10 runs)
- youxpc-simple-text-ollama:openbmb/minicpm5-2b:latest: virtual 0, system-returned 0, system 0 (parsed from 10 runs)

## Desktop evidence (Calculator / TextEdit read-back)

- youxpc-simple-ollama:qwen3:1.7b: 0/3 runs show the expected text on screen
- youxpc-ollama:qwen3:1.7b: 1/3 runs show the expected text on screen
- youxpc-simple-text-ollama:openbmb/minicpm5-2b:latest: 0/3 runs show the expected text on screen

Success for calculator tasks follows the final answer (as specified); this line is the independent on-screen check.

## Per task (successes/trials, median wall seconds over all runs)

| Task | youxpc-simple-ollama:qwen3:1.7b | youxpc-ollama:qwen3:1.7b | youxpc-simple-text-ollama:openbmb/minicpm5-2b:latest |
|---|---|---|---|
| calc-multiply | 0/1 · 5.0s | 1/1 · 15.1s | 0/1 · 0.1s |
| calc-chain | 0/1 · 18.9s | 0/1 · 100.0s | 0/1 · 0.1s |
| textedit-type | 0/1 · 13.2s | 1/1 · 8.4s | 0/1 · 0.1s |
| web-click | 0/1 · 100.0s | 1/1 · 8.7s | 0/1 · 0.1s |
| web-form | 0/1 · 18.4s | 0/1 · 14.9s | 0/1 · 0.1s |
| web-checkbox-select | 0/1 · 100.0s | 0/1 · 38.9s | 0/1 · 0.1s |
| web-read | 0/1 · 1.9s | 1/1 · 7.0s | 0/1 · 0.1s |
| web-scroll | 0/1 · 3.5s | 1/1 · 9.1s | 0/1 · 0.1s |
| web-dialog | 0/1 · 15.2s | 0/1 · 100.0s | 0/1 · 0.1s |
| web-wizard | 0/1 · 21.5s | 0/1 · 41.7s | 0/1 · 0.1s |
