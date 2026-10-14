import json
import os
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

import helpers  # noqa: F401
from helpers import FAKE_MCP
from systems import AgentContext, Options, make_system
from systems.base import count_pointers
from systems.claude_cli import load_events, parse_claude_events, YouxPCHaiku, GhostOSHaiku
from systems.codex import CodexSystem, parse_tokens_used
from systems.ollama import http_chat, mcp_tools_to_ollama, parse_text_tool_call, run_tool_loop, YouxPCOllama
from tasks import BY_ID


def stream(*extra_result):
    ev = [
        {"type": "system", "subtype": "init", "model": "claude-haiku-x", "tools": ["mcp__youxpc__pc_click"],
         "mcp_servers": [{"name": "youxpc", "status": "connected"}]},
        {"type": "assistant", "message": {"content": [
            {"type": "tool_use", "id": "t1", "name": "mcp__youxpc__pc_snapshot", "input": {}}]}},
        {"type": "user", "message": {"content": [
            {"type": "tool_result", "tool_use_id": "t1", "content": [{"type": "text", "text": "[1] button"}]}]}},
        {"type": "assistant", "message": {"content": [
            {"type": "text", "text": "clicking"},
            {"type": "tool_use", "id": "t2", "name": "mcp__youxpc__pc_click", "input": {"index": 1}}]}},
        {"type": "user", "message": {"content": [
            {"type": "tool_result", "tool_use_id": "t2",
             "content": [{"type": "text", "text": '{"success":true,"pointer":"virtual"}'}]}]}},
        {"type": "assistant", "message": {"content": [
            {"type": "tool_use", "id": "t3", "name": "mcp__youxpc__pc_click", "input": {"index": 2}}]}},
        {"type": "user", "message": {"content": [
            {"type": "tool_result", "tool_use_id": "t3", "content": 'pointer: system-returned ok'}]}},
        {"type": "result", "subtype": "success", "is_error": False, "result": "47 x 19 = 893",
         "num_turns": 4, "duration_ms": 9000, "total_cost_usd": 0.0123,
         "usage": {"input_tokens": 100, "output_tokens": 50, "cache_read_input_tokens": 1000,
                   "cache_creation_input_tokens": 200}},
    ]
    return ev


class ClaudeParseTests(unittest.TestCase):
    def test_stream_json(self):
        text = "\n".join(json.dumps(e) for e in stream())
        r = parse_claude_events(load_events(text), want_pointers=True)
        self.assertEqual(r.final_answer, "47 x 19 = 893")
        self.assertEqual(r.tool_calls, 3)
        self.assertEqual(r.input_tokens, 1300)
        self.assertEqual(r.output_tokens, 50)
        self.assertEqual(r.total_tokens, 1350)
        self.assertAlmostEqual(r.cost_usd, 0.0123)
        self.assertEqual(r.pointer_counts, {"virtual": 1, "system-returned": 1, "system": 0})
        self.assertEqual(r.model, "claude-haiku-x")
        self.assertIsNone(r.error)
        self.assertEqual(r.extra["cache_read_tokens"], 1000)

    def test_pointers_not_reported_for_ghost(self):
        r = parse_claude_events(stream(), want_pointers=False)
        self.assertIsNone(r.pointer_counts)

    def test_array_and_object_forms(self):
        self.assertEqual(len(load_events(json.dumps(stream()))), 8)
        self.assertEqual(len(load_events(json.dumps(stream()[-1]))), 1)
        r = parse_claude_events(load_events(json.dumps(stream()[-1])), False)
        self.assertEqual(r.total_tokens, 1350)

    def test_partial_run_has_nulls_not_guesses(self):
        text = "\n".join(json.dumps(e) for e in stream()[:5])      # killed before the result event
        r = parse_claude_events(load_events(text), True)
        self.assertEqual(r.tool_calls, 2)
        self.assertIsNone(r.total_tokens)
        self.assertIsNone(r.cost_usd)
        self.assertIsNone(r.final_answer)

    def test_no_events_gives_all_null(self):
        r = parse_claude_events(load_events(""), True)
        self.assertIsNone(r.tool_calls)
        self.assertIsNone(r.total_tokens)

    def test_error_and_disconnected_server(self):
        ev = stream()
        ev[0]["mcp_servers"] = [{"name": "youxpc", "status": "failed"}]
        ev[0]["tools"] = ["Bash", "mcp__youxpc__pc_click"]
        ev[-1].update(is_error=True, subtype="error_max_budget_usd", result="budget")
        r = parse_claude_events(ev, True)
        self.assertIn("not connected", r.error)
        self.assertIn("error_max_budget_usd", r.error)
        self.assertEqual(r.extra["unexpected_builtin_tools"], ["Bash"])

    def test_count_pointers(self):
        self.assertEqual(count_pointers(['{"pointer": "system"}', '"pointer":"system-returned"', "none"]),
                         {"virtual": 0, "system-returned": 1, "system": 1})


class ClaudeCommandTests(unittest.TestCase):
    def setUp(self):
        self.opts = Options(ghostos_bin="/g/ghost")
        self.ctx = AgentContext(task=BY_ID["web-click"], prompt="P", workdir=Path("."), raw_dir=Path("."),
                                label="l", timeout=10)

    def test_command_line(self):
        s = YouxPCHaiku("youxpc-haiku", self.opts)
        cmd = s.build_command("/tmp/cfg.json")
        self.assertEqual(cmd[:4], ["claude", "-p", "--model", "haiku"])
        for flag in ("--strict-mcp-config", "--verbose"):
            self.assertIn(flag, cmd)
        self.assertEqual(cmd[cmd.index("--tools") + 1], "")
        self.assertEqual(cmd[cmd.index("--allowedTools") + 1], "mcp__youxpc")
        self.assertEqual(cmd[cmd.index("--permission-mode") + 1], "dontAsk")
        self.assertNotIn("--max-turns", cmd)
        self.assertNotIn("P", cmd)                      # prompt goes on stdin

    def test_mcp_config_allowlist_and_ghost(self):
        y = YouxPCHaiku("youxpc-haiku", self.opts).mcp_config(self.ctx)["mcpServers"]["youxpc"]
        self.assertEqual(y["args"], ["mcp"])
        self.assertEqual(y["env"], {"YOUXPC_ALLOW_APPS": "com.brave.Browser"})
        g = GhostOSHaiku("ghostos-haiku", self.opts).mcp_config(self.ctx)["mcpServers"]["ghostos"]
        self.assertEqual(g["command"], "/g/ghost")
        self.assertNotIn("env", g)
        self.assertTrue(any("ghostos-bin" in p for p in GhostOSHaiku("ghostos-haiku", Options()).preflight()))

    def test_registry(self):
        self.assertIsInstance(make_system("codex", self.opts), CodexSystem)
        self.assertIsInstance(make_system("youxpc-ollama:qwen3:1.7b", self.opts), YouxPCOllama)
        self.assertEqual(make_system("youxpc-ollama:qwen3:1.7b", self.opts).model, "qwen3:1.7b")
        with self.assertRaises(SystemExit):
            make_system("nonsense", self.opts)

    def test_codex_command_and_tokens(self):
        cmd = CodexSystem("codex", self.opts).build_command(self.ctx, "/tmp/last")
        self.assertEqual(cmd[:6], ["codex", "exec", "--skip-git-repo-check", "-m", "gpt-6-luna", "--color"])
        self.assertEqual(cmd[-1], "P")
        self.assertEqual(parse_tokens_used("blah\ntokens used\n12,345\n"), 12345)
        self.assertEqual(parse_tokens_used("tokens used: 987"), 987)
        self.assertEqual(parse_tokens_used("tokens used\n1,000\n...\ntokens used\n2,500"), 2500)
        self.assertIsNone(parse_tokens_used("nothing here"))


class CodexEventTests(unittest.TestCase):
    def test_counts_calls_and_tokens(self):
        from systems.codex_mcp import parse_codex_events
        text = "\n".join([
            'Reading additional input from stdin...',
            '{"type":"thread.started"}',
            '{"type":"item.started","item":{"type":"mcp_tool_call","server":"youxpc","tool":"pc_snapshot"}}',
            '{"type":"item.completed","item":{"type":"mcp_tool_call","server":"youxpc","tool":"pc_snapshot"}}',
            '{"type":"item.started","item":{"type":"mcp_tool_call","server":"codex_apps","tool":"x"}}',
            '{"type":"item.started","item":{"type":"command_execution","command":"ls"}}',
            '{"type":"turn.completed","usage":{"input_tokens":41174,"cached_input_tokens":36096,"output_tokens":68,"reasoning_output_tokens":0}}',
        ])
        got = parse_codex_events(text, "youxpc")
        self.assertTrue(got["saw_events"])
        self.assertEqual((got["tool_calls"], got["other_mcp_calls"], got["shell_calls"]), (1, 1, 1))
        self.assertEqual((got["input_tokens"], got["cached_input_tokens"], got["output_tokens"]), (41174, 36096, 68))

    def test_plain_output_has_no_events(self):
        from systems.codex_mcp import parse_codex_events
        self.assertFalse(parse_codex_events("mcp: youxpc/pc_snapshot started\ntokens used\n27,420", "youxpc")["saw_events"])


class TextToolCallTests(unittest.TestCase):
    def test_plain_request(self):
        call = parse_text_tool_call('<tool_call>{"name": "pc_click", "arguments": {"n": "e7"}}</tool_call>')
        self.assertEqual(call, {"name": "pc_click", "arguments": {"n": "e7"}})

    def test_typographic_quotes_and_spaced_closing_tag(self):
        # What Gemma 3n E2B writes.
        call = parse_text_tool_call("<tool_call>{\u201cname\u201d: \u201cpc_look\u201d, "
                                    "\u201carguments\u201d: {\u201capp\u201d: \u201cBrave Browser\u201d}}< /tool_call>")
        self.assertEqual(call, {"name": "pc_look", "arguments": {"app": "Brave Browser"}})

    def test_valid_request_keeps_typographic_quotes_in_text(self):
        call = parse_text_tool_call('<tool_call>{"name": "pc_type", "arguments": {"text": "\u201chi\u201d"}}</tool_call>')
        self.assertEqual(call["arguments"]["text"], "\u201chi\u201d")

    def test_prose_is_not_a_request(self):
        self.assertIsNone(parse_text_tool_call("I would click the button named Delta."))


class OllamaLoopTests(unittest.TestCase):
    def scripted(self, replies):
        it = iter(replies)
        sent = []

        def chat(payload, timeout):
            sent.append(payload)
            return next(it)
        return chat, sent

    def run_loop(self, replies, **kw):
        chat, sent = self.scripted(replies)
        calls = []

        def call_tool(name, args, timeout):
            calls.append((name, args))
            return '{"pointer":"virtual"}' if name == "pc_click" else "[1] button"
        tools = [{"name": "pc_snapshot", "description": "d", "inputSchema": {"type": "object", "properties": {}}},
                 {"name": "pc_click", "description": "d", "inputSchema": {"type": "object", "properties": {}}}]
        params = dict(model="m", system_prompt="sys", user_prompt="go", tools=tools, call_tool=call_tool,
                      chat=chat, max_steps=5, deadline=time.monotonic() + 30, num_ctx=4096,
                      max_result_chars=100)
        params.update(kw)
        return run_tool_loop(**params), calls, sent

    def tc(self, name, args):
        return {"message": {"role": "assistant", "content": "", "tool_calls": [
            {"function": {"name": name, "arguments": args}}]}, "prompt_eval_count": 10, "eval_count": 3}

    def test_loop_counts_tokens_and_pointers(self):
        res, calls, sent = self.run_loop([
            self.tc("pc_snapshot", {}), self.tc("pc_click", {"index": 1}),
            {"message": {"content": "<think>x</think>893"}, "prompt_eval_count": 20, "eval_count": 2}])
        self.assertEqual(res.final_answer, "893")
        self.assertEqual(res.tool_calls, 2)
        self.assertEqual((res.input_tokens, res.output_tokens, res.total_tokens), (40, 8, 48))
        self.assertEqual(res.pointer_counts["virtual"], 1)
        self.assertEqual(sent[0]["messages"][0], {"role": "system", "content": "sys"})
        self.assertEqual(sent[0]["tools"][0]["function"]["name"], "pc_snapshot")
        self.assertEqual(sent[-1]["messages"][-1]["role"], "tool")
        self.assertIsNone(res.error)

    def test_max_steps(self):
        res, _, _ = self.run_loop([self.tc("pc_snapshot", {})] * 10, max_steps=3)
        self.assertIn("max_steps", res.error)
        self.assertEqual(res.tool_calls, 3)

    def test_unknown_tool_and_string_args_and_truncation(self):
        chat_replies = [self.tc("pc_hack", {}), self.tc("pc_click", '{"index": 2}'),
                        {"message": {"content": "ok"}, "prompt_eval_count": 1, "eval_count": 1}]
        res, calls, sent = self.run_loop(chat_replies, max_result_chars=5)
        self.assertEqual(calls, [("pc_click", {"index": 2})])
        self.assertEqual(res.tool_calls, 1)
        self.assertEqual(res.extra["truncated_tool_results"], 2)   # error text and click result both exceed 5 chars

    def test_missing_counts_stay_null(self):
        res, _, _ = self.run_loop([{"message": {"content": "hi"}}, {"message": {"content": "hi"}}])
        self.assertIsNone(res.total_tokens)
        self.assertEqual(res.final_answer, "hi")

    def test_deadline(self):
        res, _, _ = self.run_loop([self.tc("pc_snapshot", {})], deadline=time.monotonic() - 1)
        self.assertTrue(res.timed_out)

    def test_schema_conversion(self):
        out = mcp_tools_to_ollama([{"name": "a", "description": "x", "inputSchema": {"type": "object"}}])
        self.assertEqual(out, [{"type": "function", "function": {"name": "a", "description": "x",
                                                               "parameters": {"type": "object"}}}])

    def test_full_system_against_stub_ollama_and_fake_mcp(self):
        """YouxPCOllama.run with a stub HTTP Ollama and the fake MCP server (no desktop)."""
        replies = [self.tc("pc_click", {"index": 1}),
                   {"message": {"content": "done"}, "prompt_eval_count": 7, "eval_count": 2}]
        seen = []

        class H(BaseHTTPRequestHandler):
            def log_message(self, *a): pass

            def do_POST(self):
                n = int(self.headers["Content-Length"])
                seen.append(json.loads(self.rfile.read(n)))
                body = json.dumps(replies[len(seen) - 1]).encode()
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        httpd = HTTPServer(("127.0.0.1", 0), H)
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        try:
            wrapper = Path(tempfile.mkdtemp()) / "fake_youxpc"
            wrapper.write_text(f"#!/bin/sh\nexec {sys.executable} {FAKE_MCP}\n")
            wrapper.chmod(0o755)
            opts = Options(youxpc_bin=str(wrapper), ollama_url=f"http://127.0.0.1:{httpd.server_port}")
            raw = Path(tempfile.mkdtemp())
            ctx = AgentContext(task=BY_ID["web-click"], prompt="go", workdir=raw, raw_dir=raw, label="x", timeout=30)
            res = YouxPCOllama("youxpc-ollama:tiny", opts).run(ctx)
        finally:
            httpd.shutdown()
        self.assertEqual(res.final_answer, "done")
        self.assertEqual(res.tool_calls, 1)
        self.assertEqual((res.input_tokens, res.output_tokens, res.total_tokens), (17, 5, 22))
        self.assertEqual(res.pointer_counts["virtual"], 1)
        self.assertEqual(seen[0]["messages"][0]["content"], "Be careful.")   # server instructions


if __name__ == "__main__":
    unittest.main()
