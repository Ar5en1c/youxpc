import sys
from pathlib import Path

BENCH = Path(__file__).resolve().parent.parent
if str(BENCH) not in sys.path:
    sys.path.insert(0, str(BENCH))
FAKE_MCP = str(Path(__file__).resolve().parent / "fake_mcp_server.py")
