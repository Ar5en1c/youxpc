| System | Tasks passed | Median time, passed runs (s) | Median tokens, passed runs | Median tool calls | Timeouts |
|---|---|---|---|---|---|
| youxpc-simple-ollama:qwen3:1.7b | 2/10 | 23.9 | 5,190 | 2 | 0 |
| youxpc-ollama:qwen3:1.7b | 4/10 | 8.6 | 4,852 | 1 | 2 |
| youxpc-simple-text-ollama:qwen3:1.7b | 2/10 | 10.7 | 4,614 | 4 | 0 |
| youxpc-simple-text-ollama:openbmb/minicpm5-2b:latest | 0/10 | n/a | n/a | n/a | 0 |
| youxpc-text-ollama:openbmb/minicpm5-2b:latest | 0/10 | n/a | n/a | n/a | 0 |

| Task | youxpc-simple-ollama:qwen3:1.7b | youxpc-ollama:qwen3:1.7b | youxpc-simple-text-ollama:qwen3:1.7b | youxpc-simple-text-ollama:openbmb/minicpm5-2b:latest | youxpc-text-ollama:openbmb/minicpm5-2b:latest |
|---|---|---|---|---|---|
| calc-chain | 0/1 · 19s · 3,633 tok | 0/1 · 98s · 3,169 tok | 0/1 · 26s · 2,463 tok | 0/1 · 24s · 3,421 tok | 0/1 · 15s · 5,829 tok |
| calc-multiply | 0/1 · 32s · 32,471 tok | 0/1 · 14s · 5,789 tok | 0/1 · 26s · 2,451 tok | 0/1 · 22s · 1,862 tok | 0/1 · 13s · 5,653 tok |
| textedit-type | 0/1 · 13s · 8,952 tok | 1/1 · 8s · 4,865 tok | 0/1 · 2s · 902 tok | 0/1 · 6s · 1,112 tok | 0/1 · 13s · 5,673 tok |
| web-checkbox-select | 0/1 · 69s · 17,102 tok | 0/1 · 91s · 11,337 tok | 0/1 · 2s · 927 tok | 0/1 · 18s · 3,285 tok | 0/1 · 14s · 5,800 tok |
| web-click | 0/1 · 90s · 82,553 tok | 1/1 · 9s · 4,838 tok | 0/1 · 2s · 864 tok | 0/1 · 41s · 3,859 tok | 0/1 · 18s · 6,016 tok |
| web-dialog | 0/1 · 14s · 3,198 tok | 0/1 · 35s · 5,741 tok | 1/1 · 17s · 7,633 tok | 0/1 · 24s · 3,567 tok | 0/1 · 29s · 6,625 tok |
| web-form | 0/1 · 15s · 2,661 tok | 0/1 · 15s · 8,139 tok | 0/1 · 3s · 975 tok | 0/1 · 13s · 2,744 tok | 0/1 · 16s · 7,438 tok |
| web-read | 1/1 · 6s · 2,668 tok | 1/1 · 7s · 4,838 tok | 1/1 · 4s · 1,595 tok | 0/1 · 11s · 2,630 tok | 0/1 · 12s · 5,632 tok |
| web-scroll | 1/1 · 42s · 7,712 tok | 1/1 · 9s · 4,916 tok | 0/1 · 2s · 863 tok | 0/1 · 26s · 3,687 tok | 0/1 · 21s · 6,282 tok |
| web-wizard | 0/1 · 30s · 9,846 tok | 0/1 · 55s · 50,696 tok | 0/1 · 26s · 2,525 tok | 0/1 · 6s · 2,355 tok | 0/1 · 13s · 5,747 tok |

| System | Actions without the pointer | Pointer borrowed and returned | Pointer moved | Share without pointer |
|---|---|---|---|---|
| youxpc-ollama:qwen3:1.7b | 7 | 0 | 0 | 100% |
