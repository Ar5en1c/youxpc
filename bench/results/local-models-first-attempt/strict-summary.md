| System | Tasks passed | Median time, passed runs (s) | Median tokens, passed runs | Median tool calls | Timeouts |
|---|---|---|---|---|---|
| youxpc-simple-ollama:qwen3:1.7b | 0/10 | n/a | n/a | n/a | 0 |
| youxpc-ollama:qwen3:1.7b | 4/10 | 8.5 | 4,852 | 1 | 0 |
| youxpc-simple-text-ollama:openbmb/minicpm5-2b:latest | 0/10 | n/a | n/a | n/a | 0 |

| Task | youxpc-simple-ollama:qwen3:1.7b | youxpc-ollama:qwen3:1.7b | youxpc-simple-text-ollama:openbmb/minicpm5-2b:latest |
|---|---|---|---|
| calc-chain | 0/1 · 19s · 3,623 tok | 0/1 · 100s · n/a tok | 0/1 · 0s · n/a tok |
| calc-multiply | 0/1 · 5s · 712 tok | 0/1 · 15s · 5,789 tok | 0/1 · 0s · n/a tok |
| textedit-type | 0/1 · 13s · 8,952 tok | 1/1 · 8s · 4,865 tok | 0/1 · 0s · n/a tok |
| web-checkbox-select | 0/1 · 100s · n/a tok | 0/1 · 39s · 6,969 tok | 0/1 · 0s · n/a tok |
| web-click | 0/1 · 100s · n/a tok | 1/1 · 9s · 4,838 tok | 0/1 · 0s · n/a tok |
| web-dialog | 0/1 · 15s · 3,225 tok | 0/1 · 100s · n/a tok | 0/1 · 0s · n/a tok |
| web-form | 0/1 · 18s · 4,554 tok | 0/1 · 15s · 8,139 tok | 0/1 · 0s · n/a tok |
| web-read | 0/1 · 2s · 679 tok | 1/1 · 7s · 4,838 tok | 0/1 · 0s · n/a tok |
| web-scroll | 0/1 · 4s · 1,469 tok | 1/1 · 9s · 4,916 tok | 0/1 · 0s · n/a tok |
| web-wizard | 0/1 · 22s · 3,513 tok | 0/1 · 42s · 22,024 tok | 0/1 · 0s · n/a tok |

| System | Actions without the pointer | Pointer borrowed and returned | Pointer moved | Share without pointer |
|---|---|---|---|---|
| youxpc-ollama:qwen3:1.7b | 6 | 0 | 0 | 100% |
