#!/usr/bin/env python3
"""Write a publishable copy of the YouxPC benchmark runs: tool calls, answers and the
model's words, nothing else.

Raw agent output (bench/results/*/raw) is kept out of the repository. It carries
session ids, local paths and, for some tools, megabytes of screenshots. This keeps
what is needed to check a run or replay it: bench/results/<pass>/traces/<arm>/<run>.jsonl

  python3 scripts/publish_traces.py
"""
from __future__ import annotations

import json
import re
from pathlib import Path

RESULTS = Path(__file__).resolve().parent.parent / "bench" / "results"
ARMS = [("others-haiku-v1", "youxpc-haiku"), ("claude-haiku-v1", "youxpc-haiku"), ("claude-haiku-v1", "youxpc-simple-haiku")]
PORT = re.compile(r"127\.0\.0\.1:\d+")          # the test server's port differs per run
HOME = re.compile(r"/Users/[^/\s\"']+")


def clean(value):
    if isinstance(value, str):
        return HOME.sub("/Users/me", PORT.sub("127.0.0.1", value))
    if isinstance(value, list):
        return [clean(v) for v in value]
    if isinstance(value, dict):
        return {k: clean(v) for k, v in value.items()}
    return value


def convert(source: Path) -> list[dict]:
    out = []
    for line in source.read_text().splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if event.get("type") not in ("assistant", "user"):
            continue
        blocks = []
        for block in (event.get("message") or {}).get("content") or []:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "tool_use":
                blocks.append({"type": "tool_use", "id": block["id"], "name": block["name"], "input": block.get("input") or {}})
            elif block.get("type") == "text" and block.get("text", "").strip():
                blocks.append({"type": "text", "text": block["text"]})
            elif block.get("type") == "tool_result":
                content = block.get("content")
                text = content if isinstance(content, str) else " ".join(x.get("text", "") for x in content if isinstance(x, dict))
                blocks.append({"type": "tool_result", "tool_use_id": block.get("tool_use_id"), "is_error": bool(block.get("is_error")), "content": text})
        if blocks:
            out.append(clean({"type": event["type"], "message": {"content": blocks}}))
    return out


def main() -> None:
    for results_dir, arm in ARMS:
        source_dir = RESULTS / results_dir / "raw" / arm
        target_dir = RESULTS / results_dir / "traces" / arm
        target_dir.mkdir(parents=True, exist_ok=True)
        count = 0
        for source in sorted(source_dir.glob("*.stdout")):
            events = convert(source)
            (target_dir / (source.stem + ".jsonl")).write_text("".join(json.dumps(e, ensure_ascii=False) + "\n" for e in events))
            count += 1
        print(f"{results_dir}/{arm}: {count} runs")


if __name__ == "__main__":
    main()
