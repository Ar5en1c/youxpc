| System | Tasks passed | Median time, passed runs (s) | Median tokens, passed runs | Median tool calls | Timeouts |
|---|---|---|---|---|---|
| codex-youxpc | 19/20 | 22.2 | 20,660 | 3 | 0 |
| codex-youxpc-simple | 18/20 | 21.2 | 16,775 | 4 | 0 |

| Task | codex-youxpc | codex-youxpc-simple |
|---|---|---|
| calc-chain | 2/2 · 32s · 20,410 tok | 0/2 · 40s · 13,792 tok |
| calc-multiply | 2/2 · 41s · 18,102 tok | 2/2 · 46s · 33,645 tok |
| textedit-type | 2/2 · 19s · 17,158 tok | 2/2 · 14s · 15,988 tok |
| web-checkbox-select | 1/2 · 29s · 31,396 tok | 2/2 · 23s · 14,463 tok |
| web-click | 2/2 · 11s · 19,221 tok | 2/2 · 27s · 12,443 tok |
| web-dialog | 2/2 · 21s · 23,916 tok | 2/2 · 38s · 18,803 tok |
| web-form | 2/2 · 25s · 22,006 tok | 2/2 · 20s · 17,852 tok |
| web-read | 2/2 · 9s · 22,814 tok | 2/2 · 8s · 8,444 tok |
| web-scroll | 2/2 · 23s · 19,841 tok | 2/2 · 18s · 14,838 tok |
| web-wizard | 2/2 · 26s · 29,586 tok | 2/2 · 31s · 16,557 tok |

| System | Actions without the pointer | Pointer borrowed and returned | Pointer moved | Share without pointer |
|---|---|---|---|---|
| codex-youxpc | 30 | 0 | 0 | 100% |
