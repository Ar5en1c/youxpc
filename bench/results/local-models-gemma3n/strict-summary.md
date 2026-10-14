| System | Tasks passed | Median time, passed runs (s) | Median tokens, passed runs | Median tool calls | Timeouts |
|---|---|---|---|---|---|
| youxpc-text-ollama:gemma3n:e2b | 1/10 | 24.5 | 3,275 | 1 | 0 |
| youxpc-simple-text-ollama:gemma3n:e2b | 2/10 | 31.7 | 4,923 | 2 | 0 |

| Task | youxpc-text-ollama:gemma3n:e2b | youxpc-simple-text-ollama:gemma3n:e2b |
|---|---|---|
| calc-chain | 0/1 · 26s · 2,873 tok | 0/1 · 34s · 4,788 tok |
| calc-multiply | 0/1 · 23s · 2,796 tok | 0/1 · 34s · 4,758 tok |
| textedit-type | 0/1 · 83s · 8,506 tok | 0/1 · 34s · 3,616 tok |
| web-checkbox-select | 0/1 · 159s · 19,357 tok | 0/1 · 22s · 3,500 tok |
| web-click | 0/1 · 61s · 8,925 tok | 1/1 · 21s · 3,850 tok |
| web-dialog | 0/1 · 67s · 12,157 tok | 0/1 · 32s · 3,325 tok |
| web-form | 0/1 · 43s · 5,992 tok | 0/1 · 10s · 1,105 tok |
| web-read | 1/1 · 24s · 3,275 tok | 0/1 · 33s · 5,044 tok |
| web-scroll | 0/1 · 27s · 2,956 tok | 1/1 · 42s · 5,996 tok |
| web-wizard | 0/1 · 142s · 10,041 tok | 0/1 · 42s · 1,234 tok |

| System | Actions without the pointer | Pointer borrowed and returned | Pointer moved | Share without pointer |
|---|---|---|---|---|
| youxpc-text-ollama:gemma3n:e2b | 0 | 4 | 0 | 0% |
