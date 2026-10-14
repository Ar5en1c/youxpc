"""A small local model (via Ollama /api/chat) driving YouxPC.

System names:
  youxpc-ollama:<model>              native tool calling, default (core) tool profile
  youxpc-simple-ollama:<model>       native tool calling, YOUXPC_TOOLS=simple (five tools)
  youxpc-text-ollama:<model>         text protocol, core profile
  youxpc-simple-text-ollama:<model>  text protocol, simple profile

The text protocol is for models Ollama lists without the `tools` capability. The
tools are described in the system prompt and the model asks for one by writing
  <tool_call>{"name": "pc_click", "arguments": {"n": 7}}</tool_call>
Results go back as user messages. Nothing else about the run differs.

Native loop:

Loop: send messages + tool schemas -> if the reply has tool_calls, execute each through
the MCP client and append the results as `tool` messages -> repeat; a reply without
tool_calls is the final answer. Stops after --max-steps model calls or the run timeout.
Token counts are the sums of prompt_eval_count / eval_count from Ollama's responses.
The MCP server's own `instructions` are sent as the system message (Claude Code also
shows them to the model). Tool results are cut to --max-result-chars (recorded).
"""
from __future__ import annotations

import json
import os
import re
import time
import urllib.error
import urllib.request
from typing import Any, Callable, Dict, List, Optional

from mcp_client import MCPClient, MCPError
from .base import AgentContext, AgentResult, System, count_pointers, register

THINK_RE = re.compile(r"<think>.*?</think>", re.S)
# Reasoning ("thinking") output: BENCH_OLLAMA_THINK=1 asks for it, =omit leaves the
# parameter out (Ollama rejects it for models it does not list as thinking models, such as
# MiniCPM5, which then reasons in <think> tags on its own), anything else switches it off.
# On an M1, thinking multiplied step time several-fold in a trial exchange.
THINK = os.environ.get("BENCH_OLLAMA_THINK", "0")
# One generation is capped so a runaway reply cannot eat the whole run.
MAX_REPLY_TOKENS = 800
NUDGE = "You have not used a tool yet. Use one now, in the exact form shown."


def request(model: str, messages: List[Dict[str, Any]], num_ctx: int, tools: Optional[List[Dict[str, Any]]]):
    payload: Dict[str, Any] = {"model": model, "messages": messages, "stream": False,
                               "options": {"temperature": 0, "num_ctx": num_ctx, "num_predict": MAX_REPLY_TOKENS}}
    if tools is not None:
        payload["tools"] = tools
    if THINK != "omit":
        payload["think"] = THINK == "1"
    return payload


def mcp_tools_to_ollama(tools: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    out = []
    for t in tools:
        schema = t.get("inputSchema") or {"type": "object", "properties": {}}
        out.append({"type": "function", "function": {
            "name": t["name"], "description": t.get("description", ""), "parameters": schema}})
    return out


def http_chat(base_url: str, payload: Dict[str, Any], timeout: float) -> Dict[str, Any]:
    req = urllib.request.Request(base_url.rstrip("/") + "/api/chat",
                                 data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=max(1.0, timeout)) as r:
        return json.loads(r.read().decode())


def run_tool_loop(*, model: str, system_prompt: str, user_prompt: str, tools: List[Dict[str, Any]],
                  call_tool: Callable[[str, Dict[str, Any], float], str],
                  chat: Callable[[Dict[str, Any], float], Dict[str, Any]],
                  max_steps: int, deadline: float, num_ctx: int,
                  max_result_chars: int) -> AgentResult:
    res = AgentResult(model=model)
    ollama_tools = mcp_tools_to_ollama(tools)
    tool_names = {t["name"] for t in tools}
    messages: List[Dict[str, Any]] = []
    if system_prompt:
        messages.append({"role": "system", "content": system_prompt})
    messages.append({"role": "user", "content": user_prompt})
    prompt_tokens = completion_tokens = 0
    seen_counts = False
    calls = 0
    result_texts: List[str] = []
    truncated = 0
    last_content = ""
    steps = 0
    text_calls = 0
    nudged = False
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            res.timed_out = True
            res.error = "timeout (loop deadline reached)"
            break
        if steps >= max_steps:
            res.error = f"max_steps ({max_steps}) reached without a final answer"
            break
        steps += 1
        try:
            resp = chat(request(model, messages, num_ctx, ollama_tools), remaining)
        except (urllib.error.URLError, OSError, ValueError) as e:
            res.error = f"ollama request failed: {e}"
            break
        if "error" in resp:
            res.error = f"ollama error: {resp['error']}"
            break
        if "prompt_eval_count" in resp or "eval_count" in resp:
            seen_counts = True
        prompt_tokens += int(resp.get("prompt_eval_count") or 0)
        completion_tokens += int(resp.get("eval_count") or 0)
        msg = resp.get("message") or {}
        last_content = THINK_RE.sub("", msg.get("content") or "").strip()
        tool_calls = msg.get("tool_calls") or []
        if not tool_calls:
            # Small models often write the call as JSON in the reply text instead of
            # using the structured field. Run it if it names a real tool.
            written = parse_text_tool_call(last_content)
            if written is not None and written["name"] in tool_names:
                tool_calls = [{"function": written}]
                text_calls += 1
        if not tool_calls:
            if calls == 0 and not nudged:
                nudged = True
                messages.append({"role": "assistant", "content": msg.get("content") or ""})
                messages.append({"role": "user", "content": NUDGE})
                continue
            res.final_answer = last_content
            break
        messages.append({"role": "assistant", "content": msg.get("content") or "", "tool_calls": tool_calls})
        for tc in tool_calls:
            fn = tc.get("function") or {}
            name = fn.get("name", "")
            args = fn.get("arguments") or {}
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except ValueError:
                    args = {}
            if not isinstance(args, dict):
                args = {}
            if name not in tool_names:
                text = f"error: unknown tool '{name}'"
            else:
                calls += 1
                try:
                    text = call_tool(name, args, max(1.0, deadline - time.monotonic()))
                except MCPError as e:
                    text = f"error: {e}"
                result_texts.append(text)
            if len(text) > max_result_chars:
                truncated += 1
                text = text[:max_result_chars] + "\n[truncated by harness]"
            messages.append({"role": "tool", "tool_name": name, "content": text})
    res.tool_calls = calls
    if seen_counts:
        res.input_tokens, res.output_tokens = prompt_tokens, completion_tokens
        res.total_tokens = prompt_tokens + completion_tokens
    res.pointer_counts = count_pointers(result_texts)
    res.extra.update(model_calls=steps, truncated_tool_results=truncated, protocol="native", thinking=THINK,
                     calls_written_as_text=text_calls, nudged=nudged)
    if res.final_answer is None:
        res.final_answer = last_content or None
    return res


# Gemma 3n closes the tag as "< /tool_call>", hence the optional spaces.
TOOL_CALL_RE = re.compile(r"<tool_call>\s*(\{.*?\})\s*<\s*/\s*tool_call\s*>", re.S)
# MiniCPM5 writes its own tags whatever format it is shown:
#   <function_calls>\n{"name": ..., "arguments": {...}}\n</function>
FUNCTION_RE = re.compile(r"<function(?:_calls?)?>\s*(\{.*?\})\s*</function(?:_calls?)?>", re.S)
FENCED_RE = re.compile(r"```(?:json)?\s*(\{.*?\})\s*```", re.S)


STRAIGHT_QUOTES = str.maketrans({"\u201c": '"', "\u201d": '"', "\u201e": '"', "\u2018": "'", "\u2019": "'"})


def parse_text_tool_call(content: str) -> Optional[Dict[str, Any]]:
    """Find one {"name": ..., "arguments": {...}} request in a model's reply."""
    candidates = TOOL_CALL_RE.findall(content) + FUNCTION_RE.findall(content) + FENCED_RE.findall(content)
    stripped = content.strip()
    if stripped.startswith("{") and stripped.endswith("}"):
        candidates.append(stripped)
    for raw in candidates:
        try:
            obj = json.loads(raw)
        except ValueError:
            # Gemma 3n writes otherwise correct JSON with typographic quotes. Straighten
            # them only when the strict parse has failed, so quoted text is left alone
            # whenever the request was valid as written.
            try:
                obj = json.loads(raw.translate(STRAIGHT_QUOTES))
            except ValueError:
                continue
        if isinstance(obj, dict) and isinstance(obj.get("name"), str):
            args = obj.get("arguments", obj.get("parameters", {}))
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except ValueError:
                    args = {}
            return {"name": obj["name"], "arguments": args if isinstance(args, dict) else {}}
    return None


def text_protocol_prompt(tools: List[Dict[str, Any]]) -> str:
    lines = ["", "Tools you can use:"]
    for t in tools:
        props = (t.get("inputSchema") or {}).get("properties") or {}
        required = set((t.get("inputSchema") or {}).get("required") or [])
        params = ", ".join(f"{k}{'' if k in required else '?'}: {v.get('type', 'any')}" for k, v in props.items())
        lines.append(f"- {t['name']}({params}): {t.get('description', '')}")
    lines += [
        "",
        "To use a tool, reply with exactly one line in this form and nothing else:",
        '<tool_call>{"name": "TOOL_NAME", "arguments": {"KEY": VALUE}}</tool_call>',
        "You will then be sent the result. Use one tool per reply.",
        "When the task is finished, reply with a short sentence and no tool call.",
    ]
    return "\n".join(lines)


def run_text_loop(*, model: str, system_prompt: str, user_prompt: str, tools: List[Dict[str, Any]],
                  call_tool: Callable[[str, Dict[str, Any], float], str],
                  chat: Callable[[Dict[str, Any], float], Dict[str, Any]],
                  max_steps: int, deadline: float, num_ctx: int,
                  max_result_chars: int) -> AgentResult:
    """Same loop as run_tool_loop, with tool requests carried in the message text."""
    res = AgentResult(model=model)
    tool_names = {t["name"] for t in tools}
    messages: List[Dict[str, Any]] = [
        {"role": "system", "content": (system_prompt or "") + text_protocol_prompt(tools)},
        {"role": "user", "content": user_prompt},
    ]
    prompt_tokens = completion_tokens = calls = steps = truncated = malformed = 0
    seen_counts = False
    nudged = False
    result_texts: List[str] = []
    last_content = ""
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            res.timed_out = True
            res.error = "timeout (loop deadline reached)"
            break
        if steps >= max_steps:
            res.error = f"max_steps ({max_steps}) reached without a final answer"
            break
        steps += 1
        try:
            resp = chat(request(model, messages, num_ctx, None), remaining)
        except (urllib.error.URLError, OSError, ValueError) as e:
            res.error = f"ollama request failed: {e}"
            break
        if "error" in resp:
            res.error = f"ollama error: {resp['error']}"
            break
        if "prompt_eval_count" in resp or "eval_count" in resp:
            seen_counts = True
        prompt_tokens += int(resp.get("prompt_eval_count") or 0)
        completion_tokens += int(resp.get("eval_count") or 0)
        raw = (resp.get("message") or {}).get("content") or ""
        last_content = THINK_RE.sub("", raw).strip()
        call = parse_text_tool_call(last_content)
        if call is None:
            if ("<tool_call>" in last_content or "<function" in last_content) and malformed < 2:
                # Asked for a tool but the request did not parse: say so once or twice.
                malformed += 1
                messages.append({"role": "assistant", "content": raw})
                messages.append({"role": "user", "content": "That tool call was not valid JSON. Send it again in the exact form shown."})
                continue
            if calls == 0 and not nudged:
                nudged = True
                messages.append({"role": "assistant", "content": raw})
                messages.append({"role": "user", "content": NUDGE})
                continue
            res.final_answer = last_content
            break
        messages.append({"role": "assistant", "content": raw})
        name, args = call["name"], call["arguments"]
        if name not in tool_names:
            text = f"error: unknown tool '{name}'. Tools: {', '.join(sorted(tool_names))}"
        else:
            calls += 1
            try:
                text = call_tool(name, args, max(1.0, deadline - time.monotonic()))
            except MCPError as e:
                text = f"error: {e}"
            result_texts.append(text)
        if len(text) > max_result_chars:
            truncated += 1
            text = text[:max_result_chars] + "\n[truncated by harness]"
        messages.append({"role": "user", "content": f"Result of {name}:\n{text}"})
    res.tool_calls = calls
    if seen_counts:
        res.input_tokens, res.output_tokens = prompt_tokens, completion_tokens
        res.total_tokens = prompt_tokens + completion_tokens
    res.pointer_counts = count_pointers(result_texts)
    res.extra.update(model_calls=steps, truncated_tool_results=truncated, malformed_tool_calls=malformed,
                     protocol="text", thinking=THINK, nudged=nudged)
    if res.final_answer is None:
        res.final_answer = last_content or None
    return res


NAME_RE = re.compile(r"^youxpc(-simple)?(-text)?-ollama:(.+)$")


@register
class YouxPCOllama(System):
    description = "Local Ollama model driving YouxPC (variants: -simple profile, -text protocol)"
    examples = ["youxpc-ollama:<model>", "youxpc-simple-ollama:<model>",
                "youxpc-text-ollama:<model>", "youxpc-simple-text-ollama:<model>"]

    @classmethod
    def matches(cls, name): return NAME_RE.match(name) is not None

    @property
    def model(self) -> str:
        return NAME_RE.match(self.name).group(3)

    @property
    def simple_profile(self) -> bool:
        return NAME_RE.match(self.name).group(1) is not None

    @property
    def text_protocol(self) -> bool:
        return NAME_RE.match(self.name).group(2) is not None

    def preflight(self):
        probs = []
        if not os.path.exists(self.opts.youxpc_bin):
            probs.append(f"youxpc binary missing: {self.opts.youxpc_bin}")
        try:
            with urllib.request.urlopen(self.opts.ollama_url.rstrip("/") + "/api/tags", timeout=5) as r:
                names = [m["name"] for m in json.loads(r.read().decode()).get("models", [])]
            if self.model not in names:
                probs.append(f"ollama model '{self.model}' not pulled (have: {', '.join(names)})")
        except Exception as e:
            probs.append(f"ollama not reachable at {self.opts.ollama_url}: {e}")
        return probs

    def run(self, ctx: AgentContext) -> AgentResult:
        deadline = time.monotonic() + ctx.timeout
        env = dict(os.environ)
        env["YOUXPC_ALLOW_APPS"] = ",".join(ctx.task.bundle_ids)
        if self.simple_profile:
            env["YOUXPC_TOOLS"] = "simple"
        client = MCPClient([self.opts.youxpc_bin, "mcp"], env=env,
                           stderr_path=str(ctx.raw_dir / f"{ctx.label}.mcp.stderr"))
        transcript: List[str] = []

        def call_tool(name: str, args: Dict[str, Any], timeout: float) -> str:
            r = client.call_tool(name, args, timeout=timeout)
            transcript.append(json.dumps({"tool": name, "args": args, "is_error": r.is_error,
                                          "text": r.text[:4000]}))
            return ("[error] " if r.is_error else "") + r.text

        try:
            client.start()
            client.initialize()
            tools = client.list_tools()
            loop = run_text_loop if self.text_protocol else run_tool_loop
            res = loop(
                model=self.model, system_prompt=client.instructions, user_prompt=ctx.prompt,
                tools=tools, call_tool=call_tool,
                chat=lambda payload, t: http_chat(self.opts.ollama_url, payload, t),
                max_steps=self.opts.max_steps, deadline=deadline, num_ctx=self.opts.num_ctx,
                max_result_chars=self.opts.max_result_chars)
        except MCPError as e:
            res = AgentResult(model=self.model, error=f"mcp error: {e}")
        finally:
            client.close()
            (ctx.raw_dir / f"{ctx.label}.tools.jsonl").write_text("\n".join(transcript))
        return res
