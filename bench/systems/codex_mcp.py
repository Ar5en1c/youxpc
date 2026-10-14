"""OpenAI Codex CLI as the model harness, driving an MCP desktop server.

`codex-youxpc` and `codex-ghostos` use the same model, the same CLI and the same
prompt as the `codex` system. The only thing that differs between the three is the
tool stack the model is given:

  codex          Codex's own computer use (its bundled plugins)
  codex-youxpc   YouxPC over MCP, Codex's own computer use switched off
  codex-ghostos  upstream Ghost OS over MCP, Codex's own computer use switched off

That makes them a like-for-like comparison of tool stacks.

Command (overrides are per-invocation `-c key=value`, nothing is written to the
user's Codex config):

  codex exec --skip-git-repo-check -m <model> --color never -o <file>
      -c mcp_servers.<key>.command="<bin>" -c mcp_servers.<key>.args=["mcp"]
      -c mcp_servers.<key>.env={YOUXPC_ALLOW_APPS="<ids>"}        (YouxPC only)
      --ignore-user-config --disable plugins --disable apps --approve-for-me
      --disable computer_use --disable browser_use --disable browser_use_external
      "<prompt>"

`--approve-for-me` implies Codex's workspace-write sandbox, with the working directory
set to an empty scratch folder. The task prompt is the same sentence every system gets.

Token usage is Codex's own "tokens used" total. Tool calls are counted from the
"mcp: <server>/<tool> started" lines Codex prints. For YouxPC the pointer path of
each action is read from YouxPC's receipts log for the span of the run.
"""
from __future__ import annotations

import json
import os
import re
import shutil
from pathlib import Path
from typing import Dict, List, Optional

from procutil import run_with_timeout
from .base import POINTER_KEYS, AgentContext, AgentResult, System, register
from .codex import parse_tokens_used

RECEIPTS = Path(os.path.expanduser("~/.youxpc/logs/receipts.jsonl"))

# Codex's own desktop and browser control, switched off for the MCP arms.
# Feature switches (`codex features list`) behind Codex's own desktop and browser control.
NATIVE_FEATURES = ("computer_use", "browser_use", "browser_use_external")


def toml_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def receipts_size() -> int:
    try:
        return RECEIPTS.stat().st_size
    except OSError:
        return 0


def pointer_counts_since(offset: int) -> Optional[Dict[str, int]]:
    """Pointer paths YouxPC recorded after `offset` bytes of its receipts log."""
    try:
        with open(RECEIPTS, "rb") as handle:
            handle.seek(offset)
            lines = handle.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return None
    counts = {key: 0 for key in POINTER_KEYS}
    for line in lines:
        try:
            event = json.loads(line)
        except ValueError:
            continue
        pointer = event.get("pointer")
        if event.get("event") == "tool" and pointer in counts:
            counts[pointer] += 1
    return counts


class CodexMcpSystem(System):
    server_key = ""

    def server_bin(self) -> Optional[str]:
        raise NotImplementedError

    def server_args(self) -> List[str]:
        return ["mcp"]

    def server_env(self, ctx: AgentContext) -> Dict[str, str]:
        return {}

    def preflight(self) -> List[str]:
        problems = []
        if not shutil.which(self.opts.codex_bin):
            problems.append(f"'{self.opts.codex_bin}' not on PATH")
        binary = self.server_bin()
        if not binary or not Path(binary).exists():
            problems.append(f"MCP server binary missing for {self.name}: {binary}")
        return problems

    def build_command(self, ctx: AgentContext, last_msg: str) -> List[str]:
        key = self.server_key
        args = "[" + ", ".join(toml_string(a) for a in self.server_args()) + "]"
        cmd = [
            self.opts.codex_bin, "exec", "--skip-git-repo-check", "-m", self.opts.codex_model,
            "--color", "never", "-o", last_msg,
            # Events as JSON lines: tool calls and the token breakdown (cached or not).
            "--json",
            # Start from a clean configuration: none of the user's plugins or MCP servers.
            "--ignore-user-config", "--disable", "plugins",
            # Codex's hosted app connectors offer other ways to act on the Mac; one
            # run picked one of those instead of the server under test.
            "--disable", "apps",
            # Headless Codex rejects MCP tool calls that need approval; this routes
            # them through Codex's automatic reviewer instead of a person.
            "--approve-for-me",
            "-c", f"mcp_servers.{key}.command={toml_string(self.server_bin() or '')}",
            "-c", f"mcp_servers.{key}.args={args}",
        ]
        env = self.server_env(ctx)
        if env:
            pairs = ", ".join(f"{name}={toml_string(value)}" for name, value in env.items())
            cmd += ["-c", f"mcp_servers.{key}.env={{{pairs}}}"]
        for feature in NATIVE_FEATURES:
            cmd += ["--disable", feature]
        return cmd + [ctx.prompt]

    def run(self, ctx: AgentContext) -> AgentResult:
        last = ctx.raw_dir / f"{ctx.label}.lastmsg"
        out_p, err_p = ctx.raw_dir / f"{ctx.label}.stdout", ctx.raw_dir / f"{ctx.label}.stderr"
        offset = receipts_size()
        info = run_with_timeout(self.build_command(ctx, str(last)), timeout=ctx.timeout,
                                cwd=str(ctx.workdir), stdout_path=str(out_p), stderr_path=str(err_p))
        if info.spawn_error:
            return AgentResult(error=f"spawn failed: {info.spawn_error}")
        text = out_p.read_text(errors="replace") + "\n" + err_p.read_text(errors="replace")
        res = AgentResult(model=self.opts.codex_model, timed_out=info.timed_out)
        events = parse_codex_events(text, self.server_key)
        if events["saw_events"]:
            res.tool_calls = events["tool_calls"]
            res.extra["other_mcp_calls"] = events["other_mcp_calls"]
            res.extra["shell_calls"] = events["shell_calls"]
            if events["turns_reported"]:
                # input_tokens is everything the model read, cached or not. total_tokens
                # keeps the meaning of Codex's "tokens used": uncached input plus output.
                res.input_tokens = events["input_tokens"]
                res.output_tokens = events["output_tokens"]
                res.total_tokens = events["input_tokens"] - events["cached_input_tokens"] + events["output_tokens"]
                res.extra["cached_input_tokens"] = events["cached_input_tokens"]
                res.extra["reasoning_output_tokens"] = events["reasoning_output_tokens"]
        else:
            res.total_tokens = parse_tokens_used(text)
            res.tool_calls = len(re.findall(rf"^mcp: {re.escape(self.server_key)}/\S+ started", text, re.M))
            other = re.findall(r"^mcp: (\S+)/\S+ started", text, re.M)
            res.extra["other_mcp_calls"] = sum(1 for server in other if server != self.server_key)
            res.extra["shell_calls"] = len(re.findall(r"^exec\b", text, re.M))
        if self.server_key == "youxpc":
            res.pointer_counts = pointer_counts_since(offset)
        if last.exists() and last.read_text().strip():
            res.final_answer = last.read_text().strip()
        if info.timed_out:
            res.error = f"timeout after {ctx.timeout:.0f}s (process tree killed)"
        elif info.returncode != 0:
            res.error = f"codex exit {info.returncode}: {text.strip()[-300:]}"
            # The account's quota ran out: nothing about the tool under test was measured.
            if PROVIDER_LIMIT_RE.search(text):
                res.extra["provider_unavailable"] = True
        elif res.final_answer is None:
            res.error = "no final message captured"
        return res


PROVIDER_LIMIT_RE = re.compile(r"usage limit|try again at|rate limit|quota", re.I)


def parse_codex_events(text: str, server_key: str) -> dict:
    """Count tool calls and add up token usage from `codex exec --json` output."""
    out = {"saw_events": False, "turns_reported": 0, "tool_calls": 0, "other_mcp_calls": 0, "shell_calls": 0,
           "input_tokens": 0, "cached_input_tokens": 0, "output_tokens": 0, "reasoning_output_tokens": 0}
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            event = json.loads(line)
        except ValueError:
            continue
        kind = event.get("type")
        if not isinstance(kind, str):
            continue
        out["saw_events"] = True
        item = event.get("item") or {}
        if kind == "item.started" and item.get("type") == "mcp_tool_call":
            out["tool_calls" if item.get("server") == server_key else "other_mcp_calls"] += 1
        elif kind == "item.started" and item.get("type") == "command_execution":
            out["shell_calls"] += 1
        elif kind == "turn.completed" and isinstance(event.get("usage"), dict):
            out["turns_reported"] += 1
            for field in ("input_tokens", "cached_input_tokens", "output_tokens", "reasoning_output_tokens"):
                out[field] += int(event["usage"].get(field) or 0)
    return out


@register
class CodexYouxpcSystem(CodexMcpSystem):
    description = "Codex CLI model driving YouxPC over MCP (Codex's own computer use off)"
    examples = ["codex-youxpc"]
    server_key = "youxpc"

    @classmethod
    def matches(cls, name): return name == "codex-youxpc"

    def server_bin(self): return self.opts.youxpc_bin

    def server_env(self, ctx): return {"YOUXPC_ALLOW_APPS": ",".join(ctx.task.bundle_ids)}


@register
class CodexYouxpcSimpleSystem(CodexYouxpcSystem):
    description = "Codex CLI model driving YouxPC's five-tool simple profile"
    examples = ["codex-youxpc-simple"]

    @classmethod
    def matches(cls, name): return name == "codex-youxpc-simple"

    def server_env(self, ctx):
        return {"YOUXPC_ALLOW_APPS": ",".join(ctx.task.bundle_ids), "YOUXPC_TOOLS": "simple"}


@register
class CodexGhostosSystem(CodexMcpSystem):
    description = "Codex CLI model driving upstream Ghost OS over MCP (--ghostos-bin)"
    examples = ["codex-ghostos"]
    server_key = "ghostos"

    @classmethod
    def matches(cls, name): return name == "codex-ghostos"

    def server_bin(self): return self.opts.ghostos_bin

    def server_args(self): return self.opts.ghostos_args.split()
