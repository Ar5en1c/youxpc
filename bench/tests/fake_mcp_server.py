#!/usr/bin/env python3
"""Stand-in MCP stdio server for tests. Not YouxPC; touches nothing."""
import json
import sys
import time

TOOLS = [
    {"name": "pc_snapshot", "description": "snapshot", "inputSchema": {
        "type": "object", "properties": {"app": {"type": "string"}}}},
    {"name": "pc_click", "description": "click", "inputSchema": {
        "type": "object", "properties": {"index": {"type": "integer"}}, "required": ["index"]}},
    {"name": "pc_boom", "description": "always errors", "inputSchema": {"type": "object", "properties": {}}},
    {"name": "pc_slow", "description": "sleeps", "inputSchema": {"type": "object", "properties": {}}},
]


def reply(i, result=None, error=None):
    m = {"jsonrpc": "2.0", "id": i}
    if error is not None:
        m["error"] = error
    else:
        m["result"] = result
    sys.stdout.write(json.dumps(m) + "\n")
    sys.stdout.flush()


for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    msg = json.loads(line)
    method, i = msg.get("method"), msg.get("id")
    if i is None:
        continue
    if method == "initialize":
        sys.stdout.write("log line that is not json\n")
        reply(i, {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}},
                  "serverInfo": {"name": "fake", "version": "0"}, "instructions": "Be careful."})
    elif method == "tools/list":
        reply(i, {"tools": TOOLS})
    elif method == "tools/call":
        p = msg["params"]
        n = p["name"]
        if n == "pc_snapshot":
            reply(i, {"content": [{"type": "text", "text": "[1] button \"Go\""}]})
        elif n == "pc_click":
            reply(i, {"content": [{"type": "text", "text": json.dumps(
                {"success": True, "method": "ax-native", "pointer": "virtual"})}]})
        elif n == "pc_boom":
            reply(i, {"content": [{"type": "text", "text": "nope"}], "isError": True})
        elif n == "pc_slow":
            time.sleep(5)
            reply(i, {"content": [{"type": "text", "text": "late"}]})
        else:
            reply(i, error={"code": -32602, "message": "unknown tool"})
    else:
        reply(i, error={"code": -32601, "message": "method not found"})
