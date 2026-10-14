| System | Tasks passed | Median time, passed runs (s) | Median tokens, passed runs | Median tool calls | Timeouts |
|---|---|---|---|---|---|
| youxpc-ollama:qwen3:4b-instruct | 4/10 | 34.9 | 15,932 | 4 | 0 |
| youxpc-simple-ollama:qwen3:4b-instruct | 4/10 | 14.3 | 3,459 | 2 | 0 |

| Task | youxpc-ollama:qwen3:4b-instruct | youxpc-simple-ollama:qwen3:4b-instruct |
|---|---|---|
| calc-chain | 0/1 · 26s · 10,439 tok | 0/1 · 18s · 5,644 tok |
| calc-multiply | 0/1 · 29s · 10,403 tok | 0/1 · 18s · 5,591 tok |
| textedit-type | 0/1 · 27s · 9,988 tok | 1/1 · 12s · 2,294 tok |
| web-checkbox-select | 1/1 · 40s · 17,727 tok | 0/1 · 8s · 1,488 tok |
| web-click | 0/1 · 23s · 7,911 tok | 0/1 · 7s · 1,459 tok |
| web-dialog | 1/1 · 31s · 14,138 tok | 0/1 · 7s · 1,438 tok |
| web-form | 0/1 · 53s · 22,219 tok | 1/1 · 17s · 4,624 tok |
| web-read | 1/1 · 23s · 5,290 tok | 1/1 · 8s · 1,591 tok |
| web-scroll | 1/1 · 38s · 18,561 tok | 1/1 · 25s · 5,926 tok |
| web-wizard | 0/1 · 44s · 24,340 tok | 0/1 · 23s · 7,534 tok |

| System | Actions without the pointer | Pointer borrowed and returned | Pointer moved | Share without pointer |
|---|---|---|---|---|
| youxpc-ollama:qwen3:4b-instruct | 15 | 0 | 0 | 100% |
