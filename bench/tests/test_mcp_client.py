import sys
import unittest

import helpers  # noqa: F401
from helpers import FAKE_MCP
from mcp_client import MCPClient, MCPError


class MCPClientTests(unittest.TestCase):
    def test_roundtrip(self):
        with MCPClient([sys.executable, FAKE_MCP]) as c:
            self.assertEqual(c.instructions, "Be careful.")
            self.assertEqual([t["name"] for t in c.list_tools()][:2], ["pc_snapshot", "pc_click"])
            r = c.call_tool("pc_click", {"index": 3})
            self.assertFalse(r.is_error)
            self.assertIn('"pointer": "virtual"', r.text)

    def test_tool_error_flag_and_rpc_error(self):
        with MCPClient([sys.executable, FAKE_MCP]) as c:
            self.assertTrue(c.call_tool("pc_boom").is_error)
            with self.assertRaises(MCPError):
                c.call_tool("does_not_exist")

    def test_timeout_then_close_kills_server(self):
        c = MCPClient([sys.executable, FAKE_MCP]).start()
        c.initialize()
        pid = c.proc.pid
        with self.assertRaises(MCPError):
            c.call_tool("pc_slow", timeout=0.5)
        c.close()
        import os
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def test_dead_server_fails_fast(self):
        c = MCPClient([sys.executable, "-c", "pass"]).start()
        with self.assertRaises(MCPError):
            c.initialize(timeout=5)
        c.close()


if __name__ == "__main__":
    unittest.main()
