# Benchmark summary

Valid runs: 243. Infrastructure failures excluded: 0. n/a means the system did not expose that number; nothing is estimated.

## Per system

| System | Success | Wall s median (successful) | Wall s median (all runs) | Wall s mean (all runs) | Total tokens median (successful) | Total tokens median (all runs) | Tool calls median (successful) | Tool calls median (all runs) | Total cost USD | Timeouts |
|---|---|---|---|---|---|---|---|---|---|---|
| youxpc-haiku | 50/51 (98%) | 11.1 | 11.3 | 12.3 | 39,065 (n=50) | 39,196 (n=51) | 4.0 (n=50) | 4.0 (n=51) | $0.0877 (51/51 runs reported) | 0 |
| peekaboo-haiku | 22/51 (43%) | 34.1 | 28.5 | 37.3 | 747,380 (n=22) | 420,175 (n=51) | 17.5 (n=22) | 10.0 (n=51) | $1.0842 (51/51 runs reported) | 0 |
| cua-haiku | 51/51 (100%) | 22.2 | 22.2 | 25.2 | 446,476 (n=51) | 446,476 (n=51) | 7.0 (n=51) | 7.0 (n=51) | $0.4366 (51/51 runs reported) | 0 |
| playwright-haiku | 39/39 (100%) | 11.8 | 11.8 | 11.5 | 60,506 (n=39) | 60,506 (n=39) | 6.0 (n=39) | 6.0 (n=39) | $0.0754 (39/39 runs reported) | 0 |
| peekaboo-fg-haiku | 41/51 (80%) | 28.8 | 28.0 | 37.2 | 550,548 (n=41) | 514,061 (n=51) | 14.0 (n=41) | 12.0 (n=51) | $1.0028 (51/51 runs reported) | 0 |

Medians are labelled by population: *successful* = runs where the checker passed, *all runs* = every valid run including failures and timeouts. (n=k) is the number of runs that reported that metric.

## Pointer paths (YouxPC systems)

- youxpc-haiku: virtual 259, system-returned 0, system 0 (parsed from 51 runs)

## Desktop evidence (Calculator / TextEdit read-back)

- youxpc-haiku: 12/12 runs show the expected text on screen
- peekaboo-haiku: 12/12 runs show the expected text on screen
- cua-haiku: 12/12 runs show the expected text on screen
- peekaboo-fg-haiku: 12/12 runs show the expected text on screen

Success for calculator tasks follows the final answer (as specified); this line is the independent on-screen check.

## Per task (successes/trials, median wall seconds over all runs)

| Task | youxpc-haiku | peekaboo-haiku | cua-haiku | playwright-haiku | peekaboo-fg-haiku |
|---|---|---|---|---|---|
| calc-multiply | 3/3 · 8.8s | 3/3 · 25.9s | 3/3 · 29.4s | - | 3/3 · 20.5s |
| calc-chain | 3/3 · 22.4s | 3/3 · 58.6s | 3/3 · 44.0s | - | 3/3 · 46.4s |
| textedit-type | 3/3 · 6.1s | 3/3 · 11.9s | 3/3 · 9.7s | - | 3/3 · 10.1s |
| web-click | 3/3 · 8.0s | 0/3 · 22.1s | 3/3 · 12.9s | 3/3 · 8.6s | 0/3 · 24.1s |
| web-form | 3/3 · 10.3s | 3/3 · 31.1s | 3/3 · 19.8s | 3/3 · 7.2s | 3/3 · 19.8s |
| web-checkbox-select | 3/3 · 15.6s | 0/3 · 59.5s | 3/3 · 24.0s | 3/3 · 11.4s | 2/3 · 38.2s |
| web-read | 3/3 · 4.7s | 3/3 · 6.5s | 3/3 · 11.4s | 3/3 · 6.9s | 3/3 · 6.3s |
| web-scroll | 3/3 · 10.9s | 0/3 · 16.7s | 3/3 · 24.9s | 3/3 · 12.3s | 3/3 · 23.0s |
| web-dialog | 3/3 · 11.3s | 0/3 · 22.7s | 3/3 · 22.2s | 3/3 · 12.1s | 3/3 · 29.9s |
| web-wizard | 3/3 · 19.4s | 0/3 · 27.3s | 3/3 · 28.8s | 3/3 · 13.0s | 2/3 · 38.5s |
| web-rows | 2/3 · 8.7s | 0/3 · 33.3s | 3/3 · 15.5s | 3/3 · 8.0s | 2/3 · 16.7s |
| web-long-form | 3/3 · 18.9s | 2/3 · 120.9s | 3/3 · 54.4s | 3/3 · 11.8s | 2/3 · 83.1s |
| web-confirm-delete | 3/3 · 9.6s | 0/3 · 25.3s | 3/3 · 14.1s | 3/3 · 12.1s | 3/3 · 19.2s |
| web-tabs | 3/3 · 14.7s | 0/3 · 31.9s | 3/3 · 34.1s | 3/3 · 12.2s | 1/3 · 119.6s |
| web-async-search | 3/3 · 10.9s | 2/3 · 35.4s | 3/3 · 19.4s | 3/3 · 15.8s | 2/3 · 28.8s |
| web-reveal-enter | 3/3 · 12.2s | 0/3 · 25.2s | 3/3 · 24.9s | 3/3 · 11.9s | 3/3 · 29.9s |
| calc-long | 3/3 · 22.1s | 3/3 · 78.5s | 3/3 · 41.8s | - | 3/3 · 74.1s |
