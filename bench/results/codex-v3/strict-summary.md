| System | Tasks passed | Median time, passed runs (s) | Median tokens, passed runs | Median tool calls | Timeouts |
|---|---|---|---|---|---|
| codex-youxpc | 14/17 | 18.9 | 18,812 | 3 | 0 |
| codex-youxpc-simple | 14/17 | 20.4 | 16,118 | 3 | 0 |
| codex-ghostos | 13/17 | 45.0 | 28,798 | 9 | 0 |

| Task | codex-youxpc | codex-youxpc-simple | codex-ghostos |
|---|---|---|---|
| calc-chain | 0/1 · 22s · 16,133 tok | 0/1 · 14s · 11,182 tok | 1/1 · 25s · 28,798 tok |
| calc-long | 0/1 · 25s · 22,573 tok | 0/1 · 21s · 11,190 tok | 0/1 · 44s · 49,585 tok |
| calc-multiply | 1/1 · 15s · 25,306 tok | 1/1 · 14s · 11,097 tok | 1/1 · 44s · 22,819 tok |
| textedit-type | 1/1 · 9s · 13,555 tok | 1/1 · 13s · 10,429 tok | 1/1 · 15s · 21,399 tok |
| web-async-search | 1/1 · 23s · 18,637 tok | 1/1 · 25s · 21,504 tok | 0/1 · 43s · 25,663 tok |
| web-checkbox-select | 1/1 · 37s · 18,741 tok | 1/1 · 24s · 15,077 tok | 0/1 · 48s · 38,395 tok |
| web-click | 1/1 · 15s · 18,884 tok | 1/1 · 10s · 10,556 tok | 1/1 · 31s · 26,190 tok |
| web-confirm-delete | 1/1 · 21s · 20,453 tok | 1/1 · 23s · 13,121 tok | 1/1 · 48s · 27,229 tok |
| web-dialog | 1/1 · 22s · 16,459 tok | 1/1 · 17s · 17,987 tok | 1/1 · 43s · 45,892 tok |
| web-form | 1/1 · 17s · 19,087 tok | 1/1 · 19s · 20,905 tok | 1/1 · 55s · 72,316 tok |
| web-long-form | 0/1 · 23s · 19,676 tok | 0/1 · 25s · 21,349 tok | 0/1 · 202s · 57,748 tok |
| web-read | 1/1 · 8s · 15,290 tok | 1/1 · 10s · 17,160 tok | 1/1 · 28s · 37,126 tok |
| web-reveal-enter | 1/1 · 20s · 20,921 tok | 1/1 · 21s · 27,425 tok | 1/1 · 48s · 25,865 tok |
| web-rows | 1/1 · 17s · 19,534 tok | 1/1 · 21s · 33,270 tok | 1/1 · 57s · 49,596 tok |
| web-scroll | 1/1 · 18s · 18,238 tok | 1/1 · 21s · 17,272 tok | 1/1 · 45s · 23,465 tok |
| web-tabs | 1/1 · 31s · 63,243 tok | 1/1 · 22s · 11,910 tok | 1/1 · 99s · 52,975 tok |
| web-wizard | 1/1 · 25s · 18,103 tok | 1/1 · 20s · 9,383 tok | 1/1 · 53s · 48,745 tok |

| System | Actions without the pointer | Pointer borrowed and returned | Pointer moved | Share without pointer |
|---|---|---|---|---|
| codex-youxpc | 58 | 0 | 0 | 100% |
| codex-youxpc-simple | 39 | 0 | 0 | 100% |
