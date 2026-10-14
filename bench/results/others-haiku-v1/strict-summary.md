| System | Tasks passed | Median time, passed runs (s) | Median tokens, passed runs | Median tool calls | Timeouts |
|---|---|---|---|---|---|
| youxpc-haiku | 50/51 | 11.1 | 39,065 | 4 | 0 |
| peekaboo-haiku | 22/51 | 34.1 | 747,380 | 18 | 0 |
| cua-haiku | 51/51 | 22.2 | 446,476 | 7 | 0 |
| playwright-haiku | 39/39 | 11.8 | 60,506 | 6 | 0 |
| peekaboo-fg-haiku | 41/51 | 28.8 | 550,548 | 14 | 0 |

| Task | youxpc-haiku | peekaboo-haiku | cua-haiku | playwright-haiku | peekaboo-fg-haiku |
|---|---|---|---|---|---|
| calc-chain | 3/3 · 22s · 38,155 tok | 3/3 · 59s · 985,116 tok | 3/3 · 44s · 312,051 tok | - | 3/3 · 46s · 1,094,609 tok |
| calc-long | 3/3 · 22s · 40,085 tok | 3/3 · 78s · 3,347,371 tok | 3/3 · 42s · 346,857 tok | - | 3/3 · 74s · 3,742,099 tok |
| calc-multiply | 3/3 · 9s · 27,386 tok | 3/3 · 26s · 582,331 tok | 3/3 · 29s · 279,725 tok | - | 3/3 · 20s · 552,205 tok |
| textedit-type | 3/3 · 6s · 26,922 tok | 3/3 · 12s · 111,316 tok | 3/3 · 10s · 217,079 tok | - | 3/3 · 10s · 130,099 tok |
| web-async-search | 3/3 · 11s · 49,334 tok | 2/3 · 35s · 879,173 tok | 3/3 · 19s · 455,431 tok | 3/3 · 16s · 83,224 tok | 2/3 · 29s · 639,009 tok |
| web-checkbox-select | 3/3 · 16s · 48,879 tok | 0/3 · 59s · 909,127 tok | 3/3 · 24s · 538,853 tok | 3/3 · 11s · 61,233 tok | 2/3 · 38s · 947,328 tok |
| web-click | 3/3 · 8s · 27,799 tok | 0/3 · 22s · 229,612 tok | 3/3 · 13s · 333,116 tok | 3/3 · 9s · 57,699 tok | 0/3 · 24s · 402,161 tok |
| web-confirm-delete | 3/3 · 10s · 38,934 tok | 0/3 · 25s · 335,060 tok | 3/3 · 14s · 396,415 tok | 3/3 · 12s · 61,756 tok | 3/3 · 19s · 306,679 tok |
| web-dialog | 3/3 · 11s · 48,628 tok | 0/3 · 23s · 321,137 tok | 3/3 · 22s · 525,142 tok | 3/3 · 12s · 60,506 tok | 3/3 · 30s · 706,794 tok |
| web-form | 3/3 · 10s · 27,928 tok | 3/3 · 31s · 519,342 tok | 3/3 · 20s · 404,733 tok | 3/3 · 7s · 35,296 tok | 3/3 · 20s · 462,542 tok |
| web-long-form | 3/3 · 19s · 39,197 tok | 2/3 · 121s · 3,649,646 tok | 3/3 · 54s · 1,231,464 tok | 3/3 · 12s · 50,864 tok | 2/3 · 83s · 2,904,639 tok |
| web-read | 3/3 · 5s · 18,390 tok | 3/3 · 6s · 56,153 tok | 3/3 · 11s · 161,535 tok | 3/3 · 7s · 34,060 tok | 3/3 · 6s · 65,511 tok |
| web-reveal-enter | 3/3 · 12s · 60,353 tok | 0/3 · 25s · 324,096 tok | 3/3 · 25s · 531,503 tok | 3/3 · 12s · 72,762 tok | 3/3 · 30s · 341,188 tok |
| web-rows | 2/3 · 9s · 39,670 tok | 0/3 · 33s · 420,175 tok | 3/3 · 15s · 338,351 tok | 3/3 · 8s · 37,207 tok | 2/3 · 17s · 188,459 tok |
| web-scroll | 3/3 · 11s · 43,599 tok | 0/3 · 17s · 216,910 tok | 3/3 · 25s · 462,946 tok | 3/3 · 12s · 58,505 tok | 3/3 · 23s · 396,173 tok |
| web-tabs | 3/3 · 15s · 74,689 tok | 0/3 · 32s · 355,010 tok | 3/3 · 34s · 740,263 tok | 3/3 · 12s · 73,702 tok | 1/3 · 120s · 1,366,096 tok |
| web-wizard | 3/3 · 19s · 52,635 tok | 0/3 · 27s · 486,462 tok | 3/3 · 29s · 487,372 tok | 3/3 · 13s · 100,797 tok | 2/3 · 39s · 1,158,725 tok |

| System | Actions without the pointer | Pointer borrowed and returned | Pointer moved | Share without pointer |
|---|---|---|---|---|
| youxpc-haiku | 259 | 0 | 0 | 100% |
