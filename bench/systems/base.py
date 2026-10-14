"""System abstraction. Add a new system by subclassing System, setting
`matches()` and `run()`, and decorating with @register. Nothing else changes."""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Type

from tasks import Task

POINTER_RE = re.compile(r"""pointer["']?\s*[:=]\s*["']?(system-returned|virtual|system)\b""")
POINTER_KEYS = ("virtual", "system-returned", "system")


def count_pointers(texts: List[str]) -> Dict[str, int]:
    """Count one pointer path per tool-result text (first match wins)."""
    counts = {k: 0 for k in POINTER_KEYS}
    for t in texts:
        m = POINTER_RE.search(t or "")
        if m:
            counts[m.group(1)] += 1
    return counts


@dataclass
class Options:
    youxpc_bin: str = str(Path(__file__).resolve().parents[2] / ".build" / "debug" / "youxpc")
    ghostos_bin: Optional[str] = None
    ghostos_args: str = "mcp"
    claude_bin: str = "claude"
    claude_model: str = "haiku"
    claude_max_turns: Optional[int] = None
    max_budget_usd: float = 1.0
    codex_bin: str = "codex"
    codex_model: str = "gpt-6-luna"
    ollama_url: str = "http://localhost:11434"
    max_steps: int = 25
    num_ctx: int = 16384
    max_result_chars: int = 12000


@dataclass
class AgentContext:
    task: Task
    prompt: str
    workdir: Path          # clean scratch cwd for the agent process
    raw_dir: Path          # where raw stdout/stderr/transcripts are kept
    label: str             # file-name stem for this run
    timeout: float
    base_url: str = ""
    desktop: Any = None


@dataclass
class AgentResult:
    final_answer: Optional[str] = None
    tool_calls: Optional[int] = None
    input_tokens: Optional[int] = None
    output_tokens: Optional[int] = None
    total_tokens: Optional[int] = None
    cost_usd: Optional[float] = None
    pointer_counts: Optional[Dict[str, int]] = None
    error: Optional[str] = None
    timed_out: bool = False
    model: Optional[str] = None
    extra: Dict[str, Any] = field(default_factory=dict)


REGISTRY: List[Type["System"]] = []


def register(cls: Type["System"]) -> Type["System"]:
    REGISTRY.append(cls)
    return cls


class System:
    description = ""
    examples: List[str] = []

    def __init__(self, name: str, opts: Options):
        self.name = name
        self.opts = opts

    @classmethod
    def matches(cls, name: str) -> bool:
        raise NotImplementedError

    def preflight(self) -> List[str]:
        """Return a list of problems that would make a real run fail."""
        return []

    def run(self, ctx: AgentContext) -> AgentResult:
        raise NotImplementedError


def make_system(name: str, opts: Options) -> System:
    for cls in REGISTRY:
        if cls.matches(name):
            return cls(name, opts)
    known = ", ".join(e for c in REGISTRY for e in c.examples)
    raise SystemExit(f"unknown system '{name}'. Known: {known}")
