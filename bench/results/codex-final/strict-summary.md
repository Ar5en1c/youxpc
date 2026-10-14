| System | Tasks passed | Median time, passed runs (s) | Median tokens, passed runs | Median tool calls | Timeouts |
|---|---|---|---|---|---|
| codex-youxpc | 18/20 | 19.5 | 19,554 | 4 | 1 |
| codex-youxpc-simple | 18/20 | 15.8 | 14,545 | 4 | 0 |
| codex-ghostos | 20/20 | 35.0 | 26,120 | 6 | 0 |

| Task | codex-youxpc | codex-youxpc-simple | codex-ghostos |
|---|---|---|---|
| calc-chain | 1/2 · 69s · 16,273 tok | 1/2 · 36s · 22,062 tok | 2/2 · 24s · 21,530 tok |
| calc-multiply | 1/2 · 38s · 17,438 tok | 1/2 · 29s · 18,166 tok | 2/2 · 35s · 31,466 tok |
| textedit-type | 2/2 · 11s · 13,550 tok | 2/2 · 15s · 12,776 tok | 2/2 · 16s · 19,881 tok |
| web-checkbox-select | 2/2 · 28s · 19,862 tok | 2/2 · 25s · 20,734 tok | 2/2 · 46s · 38,632 tok |
| web-click | 2/2 · 11s · 20,920 tok | 2/2 · 11s · 7,631 tok | 2/2 · 20s · 17,958 tok |
| web-dialog | 2/2 · 25s · 30,066 tok | 2/2 · 18s · 17,190 tok | 2/2 · 39s · 30,464 tok |
| web-form | 2/2 · 30s · 23,479 tok | 2/2 · 20s · 13,690 tok | 2/2 · 42s · 25,318 tok |
| web-read | 2/2 · 7s · 14,904 tok | 2/2 · 8s · 11,776 tok | 2/2 · 20s · 19,455 tok |
| web-scroll | 2/2 · 20s · 21,095 tok | 2/2 · 13s · 15,230 tok | 2/2 · 51s · 42,690 tok |
| web-wizard | 2/2 · 33s · 34,829 tok | 2/2 · 33s · 19,215 tok | 2/2 · 68s · 35,840 tok |

| System | Actions without the pointer | Pointer borrowed and returned | Pointer moved | Share without pointer |
|---|---|---|---|---|
| codex-youxpc | 72 | 0 | 0 | 100% |
