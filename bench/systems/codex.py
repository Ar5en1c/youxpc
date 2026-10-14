"""OpenAI Codex CLI using its own computer-use tools.

Command: codex exec --skip-git-repo-check -m <model> --color never -o <last-msg-file> "<prompt>"
(`--color never` and `-o` only make the output parseable; `-o` is the reliable source of
the final answer.) Token usage is the number after "tokens used" that Codex prints at the
end; only a total is exposed, so input/output/tool-call counts are null. Codex ignores
YOUXPC_ALLOW_APPS, so no app allow-list is applied to it.
"""
from __future__ import annotations

import re
import shutil
from typing import List, Optional

from procutil import run_with_timeout
from .base import AgentContext, AgentResult, System, register

TOKENS_RE = re.compile(r"tokens used\W*([\d][\d,\.]*)", re.I)


def parse_tokens_used(text: str) -> Optional[int]:
    m = TOKENS_RE.findall(text)
    if not m:
        return None
    raw = m[-1].rstrip(".,").replace(",", "")
    try:
        return int(raw)
    except ValueError:
        return None


@register
class CodexSystem(System):
    description = "OpenAI Codex CLI computer use (model --codex-model)"
    examples = ["codex"]

    @classmethod
    def matches(cls, name): return name == "codex"

    def preflight(self) -> List[str]:
        return [] if shutil.which(self.opts.codex_bin) else [f"'{self.opts.codex_bin}' not on PATH"]

    def build_command(self, ctx: AgentContext, last_msg: str) -> List[str]:
        return [self.opts.codex_bin, "exec", "--skip-git-repo-check", "-m", self.opts.codex_model,
                "--color", "never", "-o", last_msg, ctx.prompt]

    def run(self, ctx: AgentContext) -> AgentResult:
        last = ctx.raw_dir / f"{ctx.label}.lastmsg"
        out_p, err_p = ctx.raw_dir / f"{ctx.label}.stdout", ctx.raw_dir / f"{ctx.label}.stderr"
        info = run_with_timeout(self.build_command(ctx, str(last)), timeout=ctx.timeout,
                                cwd=str(ctx.workdir), stdout_path=str(out_p), stderr_path=str(err_p))
        if info.spawn_error:
            return AgentResult(error=f"spawn failed: {info.spawn_error}")
        out = out_p.read_text(errors="replace")
        err = err_p.read_text(errors="replace")
        res = AgentResult(model=self.opts.codex_model, timed_out=info.timed_out)
        res.total_tokens = parse_tokens_used(out + "\n" + err)
        if last.exists() and last.read_text().strip():
            res.final_answer = last.read_text().strip()
        if info.timed_out:
            res.error = f"timeout after {ctx.timeout:.0f}s (process tree killed)"
        elif info.returncode != 0:
            res.error = f"codex exit {info.returncode}: {err.strip()[-300:]}"
        elif res.final_answer is None:
            res.error = "no final message captured"
        return res
