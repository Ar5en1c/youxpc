# Contributing to YouxPC

Thanks for looking. The most useful things, in order:

## 1. Tell us where it breaks

YouxPC has been tested on Chrome, Brave, Calculator, TextEdit and Terminal. Every other app is unknown territory. Try it on the apps you use and open an issue (there is a template) with the app and version, what you asked for, the `pc_snapshot` output and the receipt lines from `youxpc receipts --last 10`. Remove anything private first.

## 2. Write a benchmark task

Every harder task in `bench/` was written by the project's author, which is the benchmark's biggest weakness. A task written by someone else is worth more than another feature. A web task is one HTML file in `bench/pages/` that reports what the user did, plus a checker in `bench/tasks.py`; `web-rows.html` and its checker are a short example. Tasks that YouxPC fails are especially welcome.

## 3. Run the benchmark somewhere else

Another Mac, another model, another tool with its settings done properly. `bench/RESULTS.md` ends with the commands. If you know Peekaboo, Cua Driver or Playwright MCP well and think they were run badly here, say so and it will be re-run.

## 4. Fix something

```bash
git clone https://github.com/Ar5en1c/youxpc.git
cd youxpc
swift build
swift test
python3 -m unittest discover bench/tests
```

`CLAUDE.md` is the developer guide: the layout, the conventions and a long list of things that cost time to find out. Read its "Technical Gotchas" before changing how clicks, typing or snapshots work.

Rules that matter:

- No app-specific hacks. A fix has to be generic.
- Nothing is written to stdout except the MCP protocol. Log through `Log`.
- An error tells the agent what to do next.
- If a change affects behaviour an agent sees, say how you tested it.

## Credit

YouxPC is a fork of [Ghost OS](https://github.com/ghostwright/ghost-os) by Ghostwright (MIT). Fixes that apply to both projects are worth sending upstream too.
