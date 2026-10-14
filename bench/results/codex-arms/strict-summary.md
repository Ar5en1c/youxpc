| System | Tasks passed | Median time, passed runs (s) | Median tokens, passed runs | Median tool calls | Timeouts |
|---|---|---|---|---|---|
| codex-youxpc | 9/10 | 22.3 | 18,443 | 4 | 0 |
| codex-youxpc-simple | 8/10 | 19.8 | 18,090 | 4 | 0 |
| codex-ghostos | 10/10 | 28.2 | 29,778 | 5 | 0 |
| codex | 0/10 | n/a | n/a | n/a | 0 |

| Task | codex-youxpc | codex-youxpc-simple | codex-ghostos | codex |
|---|---|---|---|---|
| calc-chain | 0/1 · 14s · 15,342 tok | 1/1 · 67s · 52,113 tok | 1/1 · 24s · 26,476 tok | 0/1 · 12s · 24,902 tok |
| calc-multiply | 1/1 · 22s · 18,443 tok | 1/1 · 91s · 34,809 tok | 1/1 · 40s · 28,639 tok | 0/1 · 10s · 19,448 tok |
| textedit-type | 1/1 · 11s · 13,467 tok | 0/1 · 23s · 18,319 tok | 1/1 · 20s · 16,870 tok | 0/1 · 9s · 17,886 tok |
| web-checkbox-select | 1/1 · 36s · 25,048 tok | 0/1 · 83s · 28,833 tok | 1/1 · 49s · 46,598 tok | 0/1 · 12s · 23,679 tok |
| web-click | 1/1 · 15s · 15,229 tok | 1/1 · 11s · 7,252 tok | 1/1 · 19s · 17,559 tok | 0/1 · 14s · 20,723 tok |
| web-dialog | 1/1 · 23s · 19,557 tok | 1/1 · 17s · 16,560 tok | 1/1 · 28s · 35,187 tok | 0/1 · 19s · 25,506 tok |
| web-form | 1/1 · 22s · 18,826 tok | 1/1 · 20s · 12,916 tok | 1/1 · 30s · 35,193 tok | 0/1 · 13s · 23,493 tok |
| web-read | 1/1 · 9s · 18,431 tok | 1/1 · 11s · 14,669 tok | 1/1 · 14s · 30,917 tok | 0/1 · 10s · 7,508 tok |
| web-scroll | 1/1 · 15s · 16,755 tok | 1/1 · 20s · 19,621 tok | 1/1 · 28s · 18,108 tok | 0/1 · 12s · 23,733 tok |
| web-wizard | 1/1 · 34s · 31,314 tok | 1/1 · 35s · 29,205 tok | 1/1 · 118s · 50,183 tok | 0/1 · 10s · 13,388 tok |

| System | Actions without the pointer | Pointer borrowed and returned | Pointer moved | Share without pointer |
|---|---|---|---|---|
| codex-youxpc | 14 | 0 | 0 | 100% |
