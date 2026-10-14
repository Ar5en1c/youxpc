# YouxPC -- Developer Guide

Accessibility-first perception and execution engine that gives AI agents the
ability to see, understand, and operate any macOS application through the
accessibility tree and visual perception.

## Build & Run

```bash
swift build                          # Requires Swift 6.2+ (swiftly), macOS 14+
.build/debug/youxpc mcp               # Start MCP server (stdio)
.build/debug/youxpc setup             # Interactive first-run wizard
.build/debug/youxpc doctor            # Diagnostic health check
.build/debug/youxpc status            # Quick status
.build/debug/youxpc version           # Version info
```

Release: `scripts/build-release.sh` builds tarball, verifies 3-way version
consistency (Types.swift + server.py + youxpc-vision), and codesigns the binary.

## Architecture

MCP-first, single-threaded synchronous. No persistent daemon, no socket IPC, no
async state model. Every MCP tool call queries the AX tree fresh.

```
AI Agent (Claude Code / Cursor / any MCP client)
    |
    | MCP Protocol (stdio, auto-detects Content-Length vs NDJSON)
    |
youxpc mcp (Swift binary, @MainActor)
    |
    +-- Perception (7 tools)  -- AX tree via AXorcist
    +-- Annotate (1 tool)     -- Set-of-Marks labeled screenshots, zero ML
    +-- Actions (10 tools)    -- AX-native -> CDP -> VLM -> synthetic cascade
    +-- Wait (1 tool)         -- 6 polling condition types
    +-- Recipes (5 tools)     -- JSON workflow storage and execution
    +-- Vision (2 tools)      -- ShowUI-2B VLM via Python sidecar
    +-- Learning (3 tools)    -- CGEvent tap recording for recipe synthesis
    |
    +-- AXorcist (github.com/steipete/AXorcist, from: "0.1.0")
    +-- ScreenCaptureKit (linked framework)
```

The learning subsystem is the one exception to single-threaded: CGEvent tap runs
on a dedicated nonisolated background Thread with os_unfair_lock and CFRunLoop.

**stdout is sacred.** All MCP protocol data flows through stdout. A single stray
`print()` or `Swift.print()` will corrupt the protocol and break the connection.
All logging goes through `Log` (writes to stderr).

## Key Files

| File | What It Does |
|------|-------------|
| `Sources/YouxPC/MCP/MCPTools.swift` | All 29 tool definitions (the agent-facing contract) |
| `Sources/YouxPC/MCP/MCPDispatch.swift` | Tool routing and response formatting |
| `Sources/YouxPC/Perception/Perception.swift` | AX tree reading, semantic depth tunneling |
| `Sources/YouxPC/Perception/Snapshot.swift` | pc_snapshot: numbered compact tree, stable indices, diff mode, batched AX reads |
| `Sources/YouxPC/Actions/Actions.swift` | Multi-strategy click/type (AX -> CDP -> VLM -> synthetic) |
| `Sources/YouxPC/Pointer/PointerDriver.swift` | Pointer delivery: AX press (incl. hit-test at x/y) first, borrowed system pointer fallback |
| `Sources/YouxPC/Pointer/VirtualCursor.swift` | Click-through overlay cursor; stepped manually because the main thread blocks on stdin |
| `Sources/YouxPC/Terminal/TerminalSessions.swift` | pc_terminal: approved commands in Terminal.app, foreground-job checks, optional sandbox |
| `Sources/YouxPC/Input/TargetedKeyboard.swift` | All keystrokes: posted to one pid (cannot land in another app). Cmd/Option chords excluded |
| `Sources/YouxPC/Common/Receipts.swift` | JSON-lines record of every tool call and server start/stop; read with `youxpc receipts` |
| `Sources/YouxPC/MCP/ActionSequence.swift` | `pc_do`: several actions in one call; waits for named targets; one receipt per step |
| `Sources/YouxPC/MCP/SimpleProfile.swift` | `YOUXPC_TOOLS=simple`: six tools, full screen listing after every action |
| `Sources/CLI/ReceiptsCommand.swift` | `youxpc receipts` |
| `Sources/YouxPC/Common/PressGuard.swift` | `YOUXPC_NEVER_PRESS`: whole-word match on control names, checked in click, long-press and Return/Space |
| `Sources/YouxPC/Common/AppPolicy.swift` | Bundle-ID allow/deny policy, enforced in MCPDispatch and RecipeEngine |
| `Sources/YouxPC/Recipes/RecipeEngine.swift` | Step-by-step execution with preconditions and wait conditions |
| `Sources/YouxPC/Learning/LearningRecorder.swift` | CGEvent tap + AX enrichment for recording user actions |
| `Sources/YouxPC/Vision/VisionBridge.swift` | ShowUI-2B VLM grounding via Python sidecar |
| `Sources/YouxPC/Vision/VisionPerception.swift` | pc_ground (works) and pc_parse_screen (stub, YOLO not implemented) |
| `Sources/YouxPC/Perception/Annotate.swift` | Set-of-Marks annotation (AX-powered, zero ML) |
| `Sources/YouxPC/Screenshot/ScreenCapture.swift` | Window screenshots via ScreenCaptureKit (captures background windows) |
| `YOUXPC-MCP.md` | 13 rules for agents using YouxPC tools + recipe JSON schema |

## 29 MCP Tools

| Category | Tools |
|----------|-------|
| Perception (7) | context, state, find, read, inspect, element_at, screenshot |
| Annotate (1) | annotate |
| Actions (10) | click, type, press, hotkey, scroll, hover, long_press, drag, focus, window |
| Wait (1) | wait (urlContains, titleContains, elementExists, elementGone, urlEquals, titleEquals) |
| Recipes (5) | recipes, run, recipe_show, recipe_save, recipe_delete |
| Vision (2) | ground, parse_screen |
| Learning (3) | learn_start, learn_stop, learn_status |

**Note:** `pc_ground` sends a description to the ShowUI-2B vision model and
returns click coordinates. `pc_parse_screen` is a stub (the YOLO detection
endpoint is not yet implemented). For detecting all interactive elements without
ML, use `pc_annotate` instead (AX-powered Set-of-Marks).

## AXorcist APIs We Use

YouxPC depends on AXorcist for all accessibility tree access. Check
AXorcist source at `../AXorcist/Sources/AXorcist/` before building new features.

| API | Purpose |
|-----|---------|
| `Element.children()` | Walk element tree (checks 14+ alternative attributes) |
| `Element.title()`, `.descriptionText()`, `.value()` | Read element text |
| `Element.visibleCharacterRange()` + `.string(forRange:)` | Web content text |
| `Element.numberOfCharacters()` | Text length for range-based extraction |
| `Element.role()`, `.position()`, `.size()` | Element metadata |
| `Element.performAction(.press)` | Click elements via AX |
| `Element.typeText(text, delay:)` | Reliable typing with configurable delay |
| `Element.url()` | Read AXURL from web areas (page URL) |
| `Element.isEditable()` | Check if focused element is a text field |
| `InputDriver.click()`, `.tapKey()`, `.hotkey()` | Synthetic input |
| `AXObserverCenter` | Real-time AX notifications |
| `AccessibilityPermissions` | Permission checking |

## Code Conventions

- Swift 6.2 strict concurrency. @MainActor default isolation.
- All logging via `Log` (stderr). Never use print (corrupts MCP stdout).
- No force unwraps except in tests.
- Error responses include a `suggestion` field telling the agent what to do next.
- No app-specific hacks. All fixes must be generic.
- Version must match in 3 places: `Types.swift`, `server.py`, `youxpc-vision`.
- Semantic depth tunneling: empty layout containers (AXGroup with no content)
  cost 0 depth. Budget of 25 reaches content at 30+ DOM levels.

## Technical Gotchas

- **Chrome AXStaticText**: AXorcist's typed accessor returns nil; must use raw
  AXUIElementCopyAttributeValue to get AXValue from Chrome text elements.
- **Modifier clearing**: After every hotkey, post CGEvent flagsChanged with empty
  flags to prevent stuck modifier keys.
- **Targeted mouse events do not work**: `CGEvent.postToPid` mouse clicks leave the
  system pointer alone but never registered in Chrome (tested with and without the
  window-under-pointer fields, app active or not). Background clicks go through
  AXPress instead; see PointerDriver.swift.
- **Overlay needs servicing**: `MCPServer.waitForInput` polls stdin and calls
  `VirtualCursor.idleTick()` so the cursor can fade while no tool call is running.
- **Never send global input blind**: synthetic HID events go to whatever is frontmost when
  they arrive. `Actions.focusForInput` refuses to send unless the target is confirmed
  frontmost. Do not add asynchronous activation (e.g. `NSWorkspace.openApplication`) to
  `FocusManager.bringToFront`: a late activation once sent test keystrokes into the host's chat.
- **VS Code tree stays sparse**: setting `AXManualAccessibility` returned success but did not
  grow VS Code's tree in testing; `AXEnhancedUserInterface` was rejected. Unresolved.
- **Chromium page controls have no AXPress**: page buttons and links list only AXShowMenu and
  AXScrollToVisible, and AXPress returns success while doing nothing. `PointerDriver.activateByKey`
  focuses them through AX and posts Space/Return to the browser pid. Works in the background.
- **Chromium builds page accessibility lazily**: a first walk can show only the toolbar. What switches
  the page tree on is reading the *application element's* AXRole; walking the window does not. The web
  area then appears a moment later, so `Snapshot.wakeWebContent` reads the role and polls for up to 2 s
  (only for bundles that embed a Chromium framework). Looking once lost this race on a busy machine:
  2 of 6 first snapshots had no page while a local model was loaded. Setting AXEnhancedUserInterface
  also works but took about 2 s to take effect.
- **Cmd/Option chords posted to a pid are ignored** (Cmd+A sent to TextEdit selected nothing).
  They go through the frontmost app with focus confirmed; everything else is posted to the pid.
- **Activation is slow from a background process**: `NSRunningApplication.activate()` can take
  over a second to land. `bringToFront` waits up to ~2.7 s before reporting failure.
- **Terminal sessions**: persisted in `~/.youxpc/terminal/sessions.json`; windows are re-found by
  CG window number matched to AX frame. `open -g` keeps Terminal in the background.
- **Ids follow elements** (`Snapshot.assignNumbers`): an element keeps its id for the session (`AppState.known`).
  An element not seen before reuses the id last used for its role and name only when it is the sole such
  element in a named row, or when that id's element was last seen in the same place. Never go back to
  numbering by role + name + occurrence alone: removing one row of a table then moves every later
  button up an id, and an id read earlier presses a different row.
- **Chromium tables** expose each cell under its row and again under an AXColumn. Columns are skipped and
  elements already walked are not walked again.
- **Chromium re-creates hidden elements**: after an `aria-modal` dialog closes, the page behind comes back
  as new AX elements, so identity alone does not keep ids steady; the row anchor does.
- **Menus close asynchronously**: AXPress on a menu item returns before the choice is applied, and focusing
  another control in that window dismisses the menu and loses the choice. `pc_do` settles after a menu item.
- **NSWorkspace's app list is stale without the run loop**: use `Perception.runningApps()`, never
  `NSWorkspace.shared.runningApplications`, or an app restarted mid-session is not found.
- **Accessibility timeouts**: `MCPServer.run` sets the process-wide messaging timeout to 3 s (system default is
  about 6 s). The snapshot walk checks its deadline on every node, because with a hung app each call blocks
  for the full timeout.
- **Focus management**: Perception tools work from background. Click/type auto-save
  and restore focus. Press/hotkey/scroll/hover/long_press/drag leave target focused.
- **Transport detection**: First byte determines Content-Length (Claude Code) vs
  NDJSON (Claude Desktop) protocol.
- **Native apps**: Only show menu bar when backgrounded; need focus for full AX tree.
  Messages and Finder are exceptions (work backgrounded).
- **Chrome tabs**: Invisible to AX API (Chromium design choice). Use ctrl+tab to cycle.
- **Vision sidecar fragility**: Python dependency management has caused 3 consecutive
  patch releases (issues #1, #3, #7). The sidecar requires pinned versions of
  mlx-vlm, transformers, and mlx-lm. Always test `youxpc doctor` after touching
  vision-sidecar/ and verify on a fresh venv.

## Testing

```bash
swift test                           # Unit tests (locators, recipe names, terminal parsing)
python3 -m unittest discover bench/tests   # Benchmark harness tests (no desktop needed)
```

E2E testing: `bench/run.py` drives real apps through an agent and checks the outcome
(see bench/README.md). Otherwise run `youxpc mcp`, send JSON-RPC messages, verify responses.
Recipes should be tested 3+ times before bundling.

## Release Checklist

1. Bump version in: `Types.swift` + `server.py` + `youxpc-vision` (must match)
2. Update README: tool count, tarball URL, What's New section
3. Update YOUXPC-MCP.md if new tools or schema changes
4. `scripts/build-release.sh` produces tarball + SHA256
5. `gh release create v{VERSION} {tarball} --title "YouxPC v{VERSION}"`
6. Update Homebrew tap Formula/youxpc.rb: url + sha256 + version
7. Manual install test: extract tarball, verify binary runs, youxpc doctor
8. Verify installed version works end-to-end

## Contributing

- Recipes are the easiest contribution: JSON files in `recipes/`. See YOUXPC-MCP.md
  for the full recipe JSON schema (10 action types, parameters, wait conditions).
  Test each recipe 3+ times before submitting.
- Check AXorcist source before building new features. It may already have what you need.
- PRs for all code changes. Include what you tested and how.
