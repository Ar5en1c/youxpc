# Benchmark summary

Valid runs: 153. Infrastructure failures excluded: 0. n/a means the system did not expose that number; nothing is estimated.

## Per system

| System | Success | Wall s median (successful) | Wall s median (all runs) | Wall s mean (all runs) | Total tokens median (successful) | Total tokens median (all runs) | Tool calls median (successful) | Tool calls median (all runs) | Total cost USD | Timeouts |
|---|---|---|---|---|---|---|---|---|---|---|
| youxpc-haiku | 51/51 (100%) | 10.6 | 10.6 | 12.3 | 40,031 (n=51) | 40,031 (n=51) | 4.0 (n=51) | 4.0 (n=51) | $0.0895 (51/51 runs reported) | 0 |
| youxpc-simple-haiku | 51/51 (100%) | 10.7 | 10.7 | 12.5 | 25,680 (n=51) | 25,680 (n=51) | 3.0 (n=51) | 3.0 (n=51) | $0.0757 (51/51 runs reported) | 0 |
| ghostos-haiku | 46/51 (90%) | 18.5 | 19.1 | 23.1 | 119,106 (n=46) | 132,786 (n=51) | 10.5 (n=46) | 12.0 (n=51) | $0.2592 (51/51 runs reported) | 0 |

Medians are labelled by population: *successful* = runs where the checker passed, *all runs* = every valid run including failures and timeouts. (n=k) is the number of runs that reported that metric.

## Pointer paths (YouxPC systems)

- youxpc-haiku: virtual 262, system-returned 6, system 0 (parsed from 51 runs)
- youxpc-simple-haiku: virtual 214, system-returned 5, system 0 (parsed from 51 runs)

## Desktop evidence (Calculator / TextEdit read-back)

- youxpc-haiku: 12/12 runs show the expected text on screen
- youxpc-simple-haiku: 12/12 runs show the expected text on screen
- ghostos-haiku: 12/12 runs show the expected text on screen

Success for calculator tasks follows the final answer (as specified); this line is the independent on-screen check.

## Per task (successes/trials, median wall seconds over all runs)

| Task | youxpc-haiku | youxpc-simple-haiku | ghostos-haiku |
|---|---|---|---|
| calc-multiply | 3/3 · 11.1s | 3/3 · 15.6s | 3/3 · 14.1s |
| calc-chain | 3/3 · 11.1s | 3/3 · 11.0s | 3/3 · 20.0s |
| textedit-type | 3/3 · 7.2s | 3/3 · 8.7s | 3/3 · 10.7s |
| web-click | 3/3 · 8.2s | 3/3 · 9.5s | 3/3 · 9.9s |
| web-form | 3/3 · 10.0s | 3/3 · 9.7s | 3/3 · 11.7s |
| web-checkbox-select | 3/3 · 12.3s | 3/3 · 11.7s | 3/3 · 48.1s |
| web-read | 3/3 · 4.9s | 3/3 · 5.2s | 3/3 · 6.9s |
| web-scroll | 3/3 · 7.6s | 3/3 · 6.7s | 3/3 · 15.9s |
| web-dialog | 3/3 · 9.9s | 3/3 · 10.8s | 3/3 · 10.2s |
| web-wizard | 3/3 · 15.4s | 3/3 · 17.7s | 3/3 · 19.1s |
| web-rows | 3/3 · 10.5s | 3/3 · 6.8s | 1/3 · 23.9s |
| web-long-form | 3/3 · 16.2s | 3/3 · 16.2s | 3/3 · 64.3s |
| web-confirm-delete | 3/3 · 7.8s | 3/3 · 10.0s | 2/3 · 26.0s |
| web-tabs | 3/3 · 12.3s | 3/3 · 16.4s | 3/3 · 43.3s |
| web-async-search | 3/3 · 8.7s | 3/3 · 8.0s | 1/3 · 24.1s |
| web-reveal-enter | 3/3 · 14.7s | 3/3 · 11.7s | 3/3 · 21.8s |
| calc-long | 3/3 · 22.5s | 3/3 · 21.9s | 3/3 · 30.2s |
