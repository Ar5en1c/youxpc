| System | Tasks passed | Median time, passed runs (s) | Median tokens, passed runs | Median tool calls | Timeouts |
|---|---|---|---|---|---|
| youxpc-haiku | 51/51 | 10.6 | 40,031 | 4 | 0 |
| youxpc-simple-haiku | 51/51 | 10.7 | 25,680 | 3 | 0 |
| ghostos-haiku | 46/51 | 18.5 | 119,106 | 10 | 0 |

| Task | youxpc-haiku | youxpc-simple-haiku | ghostos-haiku |
|---|---|---|---|
| calc-chain | 3/3 · 11s · 28,252 tok | 3/3 · 11s · 18,770 tok | 3/3 · 20s · 40,730 tok |
| calc-long | 3/3 · 22s · 40,163 tok | 3/3 · 22s · 27,223 tok | 3/3 · 30s · 164,392 tok |
| calc-multiply | 3/3 · 11s · 27,879 tok | 3/3 · 16s · 26,076 tok | 3/3 · 14s · 53,342 tok |
| textedit-type | 3/3 · 7s · 26,926 tok | 3/3 · 9s · 17,628 tok | 3/3 · 11s · 36,661 tok |
| web-async-search | 3/3 · 9s · 49,380 tok | 3/3 · 8s · 31,012 tok | 1/3 · 24s · 145,849 tok |
| web-checkbox-select | 3/3 · 12s · 48,943 tok | 3/3 · 12s · 31,966 tok | 3/3 · 48s · 527,499 tok |
| web-click | 3/3 · 8s · 27,809 tok | 3/3 · 10s · 17,779 tok | 3/3 · 10s · 64,418 tok |
| web-confirm-delete | 3/3 · 8s · 38,570 tok | 3/3 · 10s · 24,504 tok | 2/3 · 26s · 233,186 tok |
| web-dialog | 3/3 · 10s · 48,703 tok | 3/3 · 11s · 30,664 tok | 3/3 · 10s · 116,046 tok |
| web-form | 3/3 · 10s · 27,925 tok | 3/3 · 10s · 17,947 tok | 3/3 · 12s · 64,491 tok |
| web-long-form | 3/3 · 16s · 49,836 tok | 3/3 · 16s · 39,574 tok | 3/3 · 64s · 589,964 tok |
| web-read | 3/3 · 5s · 18,388 tok | 3/3 · 5s · 11,848 tok | 3/3 · 7s · 37,396 tok |
| web-reveal-enter | 3/3 · 15s · 62,718 tok | 3/3 · 12s · 31,248 tok | 3/3 · 22s · 120,291 tok |
| web-rows | 3/3 · 11s · 39,677 tok | 3/3 · 7s · 19,017 tok | 1/3 · 24s · 170,340 tok |
| web-scroll | 3/3 · 8s · 43,617 tok | 3/3 · 7s · 23,407 tok | 3/3 · 16s · 144,682 tok |
| web-tabs | 3/3 · 12s · 74,532 tok | 3/3 · 16s · 48,949 tok | 3/3 · 43s · 378,781 tok |
| web-wizard | 3/3 · 15s · 49,702 tok | 3/3 · 18s · 31,762 tok | 3/3 · 19s · 202,729 tok |

| System | Actions without the pointer | Pointer borrowed and returned | Pointer moved | Share without pointer |
|---|---|---|---|---|
| youxpc-haiku | 262 | 6 | 0 | 98% |
| youxpc-simple-haiku | 214 | 5 | 0 | 98% |
