"""Claude Haiku driving an MCP server through the Claude Code CLI (`claude -p`).

Flags chosen (all verified present in `claude --help` of 2.1.293 except where noted):
  -p                         non-interactive
  --model haiku              alias; the resolved model id is read back from the init event
  --output-format stream-json --verbose
                             one JSON event per line. Needed (rather than plain `json`) so
                             tool calls and tool results can be counted/parsed; the final
                             `result` event carries usage and total_cost_usd.
  --mcp-config <file> --strict-mcp-config
                             only the server under test, no user/project MCP servers
  --tools ""                 no built-in tools (no Bash, Read, Edit, WebFetch, ...)
  --allowedTools mcp__<key>  pre-approve every tool of that one server
  --permission-mode dontAsk  anything not pre-approved is denied instead of prompting
  --no-session-persistence   leave no transcripts behind
  --disable-slash-commands   no skills
  --max-budget-usd N         per-run spend cap (a backstop, not a metric)
The prompt is sent on stdin because --mcp-config/--allowedTools/--tools are variadic and
would swallow a positional prompt. There is no --max-turns in this CLI version; the hard
wall-clock timeout and the budget cap bound a run (--claude-max-turns adds it if your
version has it).
"""
from __future__ import annotations

import json
import os
import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from procutil import run_with_timeout
from .base import AgentContext, AgentResult, Options, System, count_pointers, register
from .codex_mcp import pointer_counts_since, receipts_size


def load_events(text: str) -> List[Dict[str, Any]]:
    """Accept JSONL (stream-json), a single JSON object, or a JSON array."""
    text = text.strip()
    if not text:
        return []
    try:
        obj = json.loads(text)
        if isinstance(obj, list):
            return [e for e in obj if isinstance(e, dict)]
        if isinstance(obj, dict):
            return [obj]
    except ValueError:
        pass
    events = []
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if isinstance(e, dict):
            events.append(e)
    return events


def _block_text(content: Any) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")
    return ""


def parse_claude_events(events: List[Dict[str, Any]], want_pointers: bool) -> AgentResult:
    res = AgentResult()
    tool_ids: List[str] = []
    seen = set()
    result_texts: List[str] = []
    result_ev: Optional[Dict[str, Any]] = None
    for e in events:
        t = e.get("type")
        if t == "system" and e.get("subtype") == "init":
            res.model = e.get("model")
            bad = [s for s in e.get("mcp_servers", []) or [] if s.get("status") != "connected"]
            if bad:
                res.error = "mcp server not connected: " + json.dumps(bad)[:300]
            non_mcp = [x for x in e.get("tools", []) or [] if isinstance(x, str) and not x.startswith("mcp__")]
            if non_mcp:
                res.extra["unexpected_builtin_tools"] = non_mcp
        elif t == "assistant":
            for b in (e.get("message", {}) or {}).get("content", []) or []:
                if isinstance(b, dict) and b.get("type") == "tool_use":
                    key = b.get("id") or f"anon{len(seen)}"
                    if key not in seen:
                        seen.add(key)
                        tool_ids.append(key)
        elif t == "user":
            content = (e.get("message", {}) or {}).get("content", [])
            if isinstance(content, list):
                for b in content:
                    if isinstance(b, dict) and b.get("type") == "tool_result":
                        result_texts.append(_block_text(b.get("content")))
        elif t == "result":
            result_ev = e
    res.tool_calls = len(tool_ids) if events else None
    if want_pointers:
        res.pointer_counts = count_pointers(result_texts)
    if result_ev is not None:
        res.final_answer = result_ev.get("result") if isinstance(result_ev.get("result"), str) else None
        cost = result_ev.get("total_cost_usd", result_ev.get("cost_usd"))
        res.cost_usd = float(cost) if isinstance(cost, (int, float)) else None
        usage = result_ev.get("usage") or {}
        if isinstance(usage, dict) and "input_tokens" in usage:
            uncached = int(usage.get("input_tokens") or 0)
            cr = int(usage.get("cache_read_input_tokens") or 0)
            cc = int(usage.get("cache_creation_input_tokens") or 0)
            out = int(usage.get("output_tokens") or 0)
            res.input_tokens = uncached + cr + cc
            res.output_tokens = out
            res.total_tokens = res.input_tokens + out
            res.extra.update(input_tokens_uncached=uncached, cache_read_tokens=cr, cache_creation_tokens=cc)
        res.extra["num_turns"] = result_ev.get("num_turns")
        res.extra["cli_duration_ms"] = result_ev.get("duration_ms")
        if result_ev.get("is_error"):
            res.error = (res.error + "; " if res.error else "") + \
                f"cli error ({result_ev.get('subtype')}): {str(result_ev.get('result'))[:300]}"
    return res


PROVIDER_LIMIT_RE = re.compile(r"usage limit|rate limit|limit reached|out of extra usage|credit balance", re.I)


class ClaudeMCPSystem(System):
    """Claude Code CLI + one MCP server. Subclasses set the server command/env."""
    server_key = "desktop"
    want_pointers = False

    # to be provided by subclasses
    def server_command(self) -> Tuple[str, List[str]]: raise NotImplementedError
    def server_env(self, ctx: AgentContext) -> Dict[str, str]: return {}

    def mcp_config(self, ctx: AgentContext) -> Dict[str, Any]:
        cmd, args = self.server_command()
        cfg: Dict[str, Any] = {"command": cmd, "args": args}
        env = self.server_env(ctx)
        if env:
            cfg["env"] = env
        return {"mcpServers": {self.server_key: cfg}}

    def build_command(self, cfg_path: str) -> List[str]:
        o = self.opts
        cmd = [o.claude_bin, "-p", "--model", o.claude_model,
               "--output-format", "stream-json", "--verbose",
               "--mcp-config", cfg_path, "--strict-mcp-config",
               "--tools", "",
               "--allowedTools", f"mcp__{self.server_key}",
               "--permission-mode", "dontAsk",
               "--no-session-persistence", "--disable-slash-commands",
               "--max-budget-usd", f"{o.max_budget_usd:g}"]
        if o.claude_max_turns:
            cmd += ["--max-turns", str(o.claude_max_turns)]
        return cmd

    def run(self, ctx: AgentContext) -> AgentResult:
        cfg_path = ctx.raw_dir / f"{ctx.label}.mcp.json"
        cfg_path.write_text(json.dumps(self.mcp_config(ctx), indent=2))
        out_p, err_p = ctx.raw_dir / f"{ctx.label}.stdout", ctx.raw_dir / f"{ctx.label}.stderr"
        env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}
        receipts_offset = receipts_size()
        info = run_with_timeout(self.build_command(str(cfg_path)), timeout=ctx.timeout, env=env,
                                cwd=str(ctx.workdir), stdin_text=self.prompt_for(ctx),
                                stdout_path=str(out_p), stderr_path=str(err_p))
        if info.spawn_error:
            return AgentResult(error=f"spawn failed: {info.spawn_error}")
        res = parse_claude_events(load_events(out_p.read_text(errors="replace")), self.want_pointers)
        res.timed_out = info.timed_out
        if self.want_pointers:
            # From YouxPC's receipts, which have one entry per action even inside pc_do.
            res.pointer_counts = pointer_counts_since(receipts_offset)
        if info.timed_out:
            res.error = ((res.error + "; ") if res.error else "") + f"timeout after {ctx.timeout:.0f}s (process tree killed)"
        elif res.final_answer is None and not res.error:
            tail = err_p.read_text(errors="replace").strip()[-300:]
            res.error = f"no result event (exit {info.returncode}): {tail}"
        # The account's limit was reached: nothing about the tool under test was measured.
        if res.error and PROVIDER_LIMIT_RE.search(res.error):
            res.extra["provider_unavailable"] = True
        return res

    def prompt_for(self, ctx: AgentContext) -> str:
        """The task as this tool stack needs to hear it. Desktop tools find the open app."""
        return ctx.prompt

    def preflight(self) -> List[str]:
        import shutil
        probs = []
        if not shutil.which(self.opts.claude_bin):
            probs.append(f"'{self.opts.claude_bin}' not on PATH")
        return probs


@register
class YouxPCHaiku(ClaudeMCPSystem):
    server_key = "youxpc"
    want_pointers = True
    description = "Claude (--claude-model, default haiku) driving YouxPC via `claude -p`"
    examples = ["youxpc-haiku"]

    @classmethod
    def matches(cls, name): return name == "youxpc-haiku"

    def server_command(self): return self.opts.youxpc_bin, ["mcp"]

    def server_env(self, ctx): return {"YOUXPC_ALLOW_APPS": ",".join(ctx.task.bundle_ids)}

    def preflight(self):
        probs = super().preflight()
        if not Path(self.opts.youxpc_bin).exists():
            probs.append(f"youxpc binary missing: {self.opts.youxpc_bin}")
        return probs


@register
class YouxPCSimpleHaiku(YouxPCHaiku):
    description = "Same as youxpc-haiku with YouxPC's simple profile (YOUXPC_TOOLS=simple)"
    examples = ["youxpc-simple-haiku"]

    @classmethod
    def matches(cls, name): return name == "youxpc-simple-haiku"

    def server_env(self, ctx):
        return dict(super().server_env(ctx), YOUXPC_TOOLS="simple")


@register
class YouxPCNoDoHaiku(YouxPCHaiku):
    """The default profile with pc_do denied to the model, so every action is its own call.
    The server and its tool list are unchanged; only the CLI refuses pc_do. This isolates
    batching from everything else (tool-list size, snapshot format, ids)."""
    description = "Same as youxpc-haiku with pc_do denied (--disallowedTools mcp__youxpc__pc_do)"
    examples = ["youxpc-nodo-haiku"]

    @classmethod
    def matches(cls, name): return name == "youxpc-nodo-haiku"

    def build_command(self, cfg_path: str) -> List[str]:
        return super().build_command(cfg_path) + ["--disallowedTools", f"mcp__{self.server_key}__pc_do"]


@register
class GhostOSHaiku(ClaudeMCPSystem):
    server_key = "ghostos"
    want_pointers = False
    description = "Same as youxpc-haiku but the MCP server is upstream Ghost OS (--ghostos-bin)"
    examples = ["ghostos-haiku"]

    @classmethod
    def matches(cls, name): return name == "ghostos-haiku"

    def server_command(self):
        return self.opts.ghostos_bin or "", self.opts.ghostos_args.split()

    def preflight(self):
        probs = super().preflight()
        if not self.opts.ghostos_bin:
            probs.append("--ghostos-bin is required for ghostos-haiku")
        elif not Path(self.opts.ghostos_bin).exists():
            probs.append(f"ghost binary missing: {self.opts.ghostos_bin}")
        return probs


# -- other tools, same model ---------------------------------------------------
# Each of these is somebody else's MCP server driven by the same `claude -p`
# command, so the comparison changes the tool and nothing else.

@register
class PlaywrightHaiku(ClaudeMCPSystem):
    """Microsoft's Playwright MCP. It drives its own browser, so it can only do the web
    tasks, and it has to be told the page's address instead of finding an open window."""
    server_key = "playwright"
    want_pointers = False
    description = "Claude driving Playwright MCP (web tasks only; own headless browser)"
    examples = ["playwright-haiku"]
    PACKAGE = "@playwright/mcp@0.0.83"

    @classmethod
    def matches(cls, name): return name == "playwright-haiku"

    def server_command(self):
        # BENCH_PLAYWRIGHT_MCP=/path/to/@playwright/mcp/cli.js skips npx's start-up on every run.
        cli = os.environ.get("BENCH_PLAYWRIGHT_MCP")
        if cli:
            return "node", [cli, "--headless", "--isolated"]
        return "npx", ["-y", self.PACKAGE, "--headless", "--isolated"]

    def prompt_for(self, ctx: AgentContext) -> str:
        task = ctx.task
        if task.kind != "web":
            raise RuntimeError("Playwright MCP has no access to desktop apps; run it on web tasks only")
        return (f"{task.sentence} The page is at {ctx.base_url}/{task.page}.html ; open it with your browser tools. "
                "When you are done, reply with a short final message.")


@register
class PeekabooHaiku(ClaudeMCPSystem):
    """Peekaboo (openclaw/Peekaboo, MIT): screenshots plus an accessibility map."""
    server_key = "peekaboo"
    want_pointers = False
    description = "Claude driving Peekaboo's MCP server"
    examples = ["peekaboo-haiku"]
    PACKAGE = "@steipete/peekaboo@4.9.2"

    @classmethod
    def matches(cls, name): return name == "peekaboo-haiku"

    def server_command(self):
        # BENCH_PEEKABOO_BIN=/path/to/peekaboo runs the native binary without npx or its restart wrapper.
        binary = os.environ.get("BENCH_PEEKABOO_BIN")
        if binary:
            return binary, ["mcp", "serve"]
        return "npx", ["-y", "-p", self.PACKAGE, "peekaboo-mcp"]


@register
class PeekabooForegroundHaiku(PeekabooHaiku):
    """Peekaboo with --allow-foreground. Its server is background-only by default and in
    that mode could not press buttons inside a web page; this is its like-for-like setting."""
    description = "Claude driving Peekaboo's MCP server with --allow-foreground"
    examples = ["peekaboo-fg-haiku"]

    @classmethod
    def matches(cls, name): return name == "peekaboo-fg-haiku"

    def server_command(self):
        command, args = super().server_command()
        return command, args + ["--allow-foreground"]


@register
class CuaDriverHaiku(ClaudeMCPSystem):
    """Cua Driver (trycua/cua, MIT driver). Needs its own Accessibility and Screen
    Recording grants for CuaDriver.app before it can act."""
    server_key = "cua"
    want_pointers = False
    description = "Claude driving Cua Driver's MCP server (cua-driver mcp)"
    examples = ["cua-haiku"]

    @classmethod
    def matches(cls, name): return name == "cua-haiku"

    def server_command(self): return os.environ.get("BENCH_CUA_BIN", "cua-driver"), ["mcp"]
