# Benchmark summary

Valid runs: 102. Infrastructure failures excluded: 0. n/a means the system did not expose that number; nothing is estimated.

## Per system

| System | Success | Wall s median (successful) | Wall s median (all runs) | Wall s mean (all runs) | Total tokens median (successful) | Total tokens median (all runs) | Tool calls median (successful) | Tool calls median (all runs) | Total cost USD | Timeouts |
|---|---|---|---|---|---|---|---|---|---|---|
| youxpc-haiku | 51/51 (100%) | 9.8 | 9.8 | 11.6 | 41,220 (n=51) | 41,220 (n=51) | 4.0 (n=51) | 4.0 (n=51) | $0.0965 (51/51 runs reported) | 0 |
| youxpc-nodo-haiku | 51/51 (100%) | 10.8 | 10.8 | 15.3 | 48,594 (n=51) | 48,594 (n=51) | 5.0 (n=51) | 5.0 (n=51) | $0.1213 (51/51 runs reported) | 0 |

Medians are labelled by population: *successful* = runs where the checker passed, *all runs* = every valid run including failures and timeouts. (n=k) is the number of runs that reported that metric.

## Pointer paths (YouxPC systems)

- youxpc-haiku: virtual 281, system-returned 1, system 0 (parsed from 51 runs)
- youxpc-nodo-haiku: virtual 295, system-returned 2, system 0 (parsed from 51 runs)

## Desktop evidence (Calculator / TextEdit read-back)

- youxpc-haiku: 12/12 runs show the expected text on screen
- youxpc-nodo-haiku: 12/12 runs show the expected text on screen

Success for calculator tasks follows the final answer (as specified); this line is the independent on-screen check.

## Per task (successes/trials, median wall seconds over all runs)

| Task | youxpc-haiku | youxpc-nodo-haiku |
|---|---|---|
| calc-multiply | 3/3 · 8.0s | 3/3 · 19.1s |
| calc-chain | 3/3 · 18.3s | 3/3 · 29.8s |
| textedit-type | 3/3 · 6.5s | 3/3 · 6.1s |
| web-click | 3/3 · 6.8s | 3/3 · 6.7s |
| web-form | 3/3 · 8.3s | 3/3 · 10.2s |
| web-checkbox-select | 3/3 · 12.8s | 3/3 · 11.5s |
| web-read | 3/3 · 5.0s | 3/3 · 6.1s |
| web-scroll | 3/3 · 7.0s | 3/3 · 8.2s |
| web-dialog | 3/3 · 10.0s | 3/3 · 9.4s |
| web-wizard | 3/3 · 16.9s | 3/3 · 13.3s |
| web-rows | 3/3 · 7.7s | 3/3 · 7.6s |
| web-long-form | 3/3 · 17.0s | 3/3 · 17.9s |
| web-confirm-delete | 3/3 · 8.9s | 3/3 · 8.7s |
| web-tabs | 3/3 · 13.8s | 3/3 · 13.2s |
| web-async-search | 3/3 · 9.4s | 3/3 · 10.0s |
| web-reveal-enter | 3/3 · 11.5s | 3/3 · 10.8s |
| calc-long | 3/3 · 24.0s | 3/3 · 51.1s |
