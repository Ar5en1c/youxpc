# Benchmark summary

Valid runs: 50. Infrastructure failures excluded: 0. n/a means the system did not expose that number; nothing is estimated.

## Per system

| System | Success | Wall s median (successful) | Wall s median (all runs) | Wall s mean (all runs) | Total tokens median (successful) | Total tokens median (all runs) | Tool calls median (successful) | Tool calls median (all runs) | Total cost USD | Timeouts |
|---|---|---|---|---|---|---|---|---|---|---|
| youxpc-simple-ollama:qwen3:1.7b | 2/10 (20%) | 23.9 | 24.3 | 33.1 | 5,190 (n=2) | 8,332 (n=10) | 2.5 (n=2) | 8.5 (n=10) | n/a | 0 |
| youxpc-ollama:qwen3:1.7b | 5/10 (50%) | 8.7 | 14.6 | 34.3 | 4,865 (n=5) | 5,328 (n=10) | 1.0 (n=5) | 2.5 (n=10) | n/a | 2 |
| youxpc-simple-text-ollama:qwen3:1.7b | 2/10 (20%) | 10.7 | 3.5 | 11.0 | 4,614 (n=2) | 1,285 (n=10) | 3.5 (n=2) | 0.0 (n=10) | n/a | 0 |
| youxpc-simple-text-ollama:openbmb/minicpm5-2b:latest | 0/10 (0%) | n/a | 20.1 | 19.1 | n/a (n=0) | 3,014 (n=10) | n/a (n=0) | 0.0 (n=10) | n/a | 0 |
| youxpc-text-ollama:openbmb/minicpm5-2b:latest | 0/10 (0%) | n/a | 14.4 | 16.4 | n/a (n=0) | 5,814 (n=10) | n/a (n=0) | 0.0 (n=10) | n/a | 0 |

Medians are labelled by population: *successful* = runs where the checker passed, *all runs* = every valid run including failures and timeouts. (n=k) is the number of runs that reported that metric.

## Pointer paths (YouxPC systems)

- youxpc-simple-ollama:qwen3:1.7b: virtual 0, system-returned 0, system 0 (parsed from 10 runs)
- youxpc-ollama:qwen3:1.7b: virtual 7, system-returned 0, system 0 (parsed from 10 runs)
- youxpc-simple-text-ollama:qwen3:1.7b: virtual 0, system-returned 0, system 0 (parsed from 10 runs)
- youxpc-simple-text-ollama:openbmb/minicpm5-2b:latest: virtual 0, system-returned 0, system 0 (parsed from 10 runs)
- youxpc-text-ollama:openbmb/minicpm5-2b:latest: virtual 0, system-returned 0, system 0 (parsed from 10 runs)

## Desktop evidence (Calculator / TextEdit read-back)

- youxpc-simple-ollama:qwen3:1.7b: 0/3 runs show the expected text on screen
- youxpc-ollama:qwen3:1.7b: 1/3 runs show the expected text on screen
- youxpc-simple-text-ollama:qwen3:1.7b: 0/3 runs show the expected text on screen
- youxpc-simple-text-ollama:openbmb/minicpm5-2b:latest: 0/3 runs show the expected text on screen
- youxpc-text-ollama:openbmb/minicpm5-2b:latest: 0/3 runs show the expected text on screen

Success for calculator tasks follows the final answer (as specified); this line is the independent on-screen check.

## Per task (successes/trials, median wall seconds over all runs)

| Task | youxpc-simple-ollama:qwen3:1.7b | youxpc-ollama:qwen3:1.7b | youxpc-simple-text-ollama:qwen3:1.7b | youxpc-simple-text-ollama:openbmb/minicpm5-2b:latest | youxpc-text-ollama:openbmb/minicpm5-2b:latest |
|---|---|---|---|---|---|
| calc-multiply | 0/1 · 32.5s | 1/1 · 14.4s | 0/1 · 26.0s | 0/1 · 22.0s | 0/1 · 12.9s |
| calc-chain | 0/1 · 18.6s | 0/1 · 98.5s | 0/1 · 26.1s | 0/1 · 24.0s | 0/1 · 15.2s |
| textedit-type | 0/1 · 12.9s | 1/1 · 8.4s | 0/1 · 2.1s | 0/1 · 5.9s | 0/1 · 12.9s |
| web-click | 0/1 · 90.4s | 1/1 · 8.7s | 0/1 · 1.6s | 0/1 · 41.5s | 0/1 · 17.6s |
| web-form | 0/1 · 15.4s | 0/1 · 14.9s | 0/1 · 2.9s | 0/1 · 12.5s | 0/1 · 16.4s |
| web-checkbox-select | 0/1 · 68.8s | 0/1 · 91.3s | 0/1 · 2.4s | 0/1 · 18.2s | 0/1 · 13.7s |
| web-read | 1/1 · 5.5s | 1/1 · 7.0s | 1/1 · 4.0s | 0/1 · 11.0s | 0/1 · 12.3s |
| web-scroll | 1/1 · 42.3s | 1/1 · 9.1s | 0/1 · 1.5s | 0/1 · 25.6s | 0/1 · 21.2s |
| web-dialog | 0/1 · 14.0s | 0/1 · 35.3s | 1/1 · 17.5s | 0/1 · 23.7s | 0/1 · 29.5s |
| web-wizard | 0/1 · 30.1s | 0/1 · 55.1s | 0/1 · 26.2s | 0/1 · 6.1s | 0/1 · 12.6s |
