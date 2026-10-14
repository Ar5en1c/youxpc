# YouxPC v2 - MCP Agent Instructions

You have YouxPC, a tool that lets you see and operate any macOS application
through the accessibility tree AND visual perception. Every button, text field,
link, and label is available -- either through the AX tree (native apps) or
vision-based grounding (web apps where Chrome exposes everything as AXGroup).

You can perceive the screen, click, type, hover, drag, long-press, scroll,
press keys, manage windows, wait for conditions and run saved recipes.

## Rule 0: Snapshot, Then Act by Number

Call `pc_snapshot app:"<App>"` first. It returns one short line per element
in the focused window, with interactive ones numbered:

```
toolbar
  [e5] textfield "Address and search bar" = "example.com"
web "Example"
  [e7] button "Compose"
```

Pass that number as `index` to `pc_click`, `pc_type`, `pc_hover` or
`pc_long_press`. No `app` or `query` is needed with an index.

- An id stays with its element for the whole session. When an element goes
  away its id is retired, not given to another element.
- After the first snapshot of a window you get only the changes: `+` added,
  `-` removed, `~` changed. Pass `full:true` for the whole list again.
- Action results carry `changes`: what the action changed. Read that instead
  of taking another snapshot. If an id is reported as gone, snapshot again.
- Content outside the window's visible area is left out. Scroll, then snapshot.
- A table is listed row by row; each row's controls are indented under a
  `row "<first text>"` line.
- A click by name is refused when several controls share that name. The error
  lists each one's id and row; use the id.

When you already know the next few steps, send them in one call:

```
pc_do steps:[{"type":"Ada","into":"e14"},{"type":"ada@example.test","into":"e15"},{"click":"Submit"}]
```

A step is `click`, `type` (with `into`), `key`, `scroll` or `wait`. A target
written with its `e` is an id; anything else is a name, looked up when that
step runs, so it can be something an earlier step made appear. Steps stop at
the first failure. The answer lists each step's outcome and the net change;
read the change before saying the task is done. For keys and items labelled
with a digit or one character, use the name (`"7"`), not the id.

Use `pc_find`, `pc_read` and screenshots only when the snapshot does not
show what you need.

## Rule 1: Always Check Recipes First

Before doing ANY multi-step task manually, call `pc_recipes`.

If a recipe exists for what you need, use `pc_run` with the recipe name
and parameters. Recipes are tested, reliable, and faster than manual steps.

## Rule 2: Orient Before Acting

Before interacting with any app, call `pc_context` with the app name.

This tells you: which app/window is active, the current URL (for browsers),
what element is focused, and what interactive elements are visible.

**If you skip this, you will click the wrong thing.**

## Rule 3: How to Find Elements

Use `pc_find` with the most specific identifier available:
- `dom_id` for web apps (most reliable, bypasses depth limits)
- `identifier` for native apps with developer IDs
- `query` + `role` for general searches (e.g., query:"Compose", role:"AXButton")
- `query` alone as a fallback

Use `pc_inspect` to examine an element before acting on it.
Use `pc_element_at` to identify elements from screenshots.

## Rule 4: How Focus Works

**Perception tools work from background** (no focus needed):
- pc_context, pc_state, pc_find, pc_read, pc_inspect,
  pc_element_at, pc_screenshot

Note: `pc_screenshot` captures windows even when they are behind other
windows or in another Space. It does NOT need the app to be focused. If all of
an app's windows are closed (not just minimized), screenshot will return an
error -- you cannot capture what does not exist.

**Click and type try AX-native first** (no focus), then synthetic fallback (auto-focuses):
- pc_click, pc_type

**Press, hotkey, scroll, hover, long_press, drag need focus** - always pass the `app` parameter:
- pc_press, pc_hotkey, pc_scroll, pc_hover, pc_long_press, pc_drag

Focus is automatically saved and restored after click and type. Other action tools leave the target app focused.

**The `pointer` field tells you which pointer an action used:**
- `virtual` - the control was pressed through accessibility. No mouse event was
  sent, the app stayed in the background, and the user's pointer did not move.
  `pc_click` does this for element clicks and for x/y clicks that land on a
  button, link, checkbox, tab or menu item.
- `system-returned` - real mouse events were needed (canvas, custom-drawn UI,
  right/double click). The user's pointer jumped to the target and was put back.
- `system` - the real pointer moved and stayed there (`pc_hover` always does).

Prefer targets that resolve to `virtual`: they do not interrupt the user.

## Rule 5: Key Patterns

### Navigate Chrome to a URL
```
pc_hotkey keys:["cmd","l"] app:"Chrome"  -> address bar focused
pc_type text:"https://example.com"       -> URL entered
pc_press key:"return" app:"Chrome"       -> navigate
pc_wait condition:"urlContains" value:"example.com" app:"Chrome"
```

### Fill a form
```
pc_click query:"Compose" app:"Chrome"    -> click button
pc_type text:"hello@example.com" into:"To" app:"Chrome"
pc_press key:"tab" app:"Chrome"          -> move to next field
pc_type text:"Subject line" into:"Subject" app:"Chrome"
```

### Annotate for visual orientation
```
pc_annotate app:"Chrome"
-> Returns labeled screenshot + text index
-> [1] Button "Send" — click: (620, 350)
-> Use pc_click x:620 y:350 to click any labeled element
```

### Hover to reveal tooltips or menus
```
pc_hover query:"Help" app:"Preview"
pc_hover x:500 y:300 app:"Chrome"
```

### Drag files, sliders, or list items
```
pc_drag query:"document.pdf" to_x:500 to_y:300 app:"Finder"
pc_drag from_x:200 from_y:400 to_x:600 to_y:400 app:"Finder"
```

### Wait instead of guessing
```
pc_wait condition:"elementExists" value:"Send" app:"Chrome"
pc_wait condition:"urlContains" value:"inbox" timeout:15 app:"Chrome"
pc_wait condition:"elementGone" value:"Loading" app:"Chrome"
```

## Rule 6: Vision Fallback for Web Apps

When `pc_find` or `pc_click` can't locate an element (common in web apps
like Gmail, Slack, etc. where Chrome exposes everything as AXGroup), YouxPC
automatically falls back to VLM-based vision grounding if the vision sidecar
is running.

You can also use vision tools directly:

### pc_ground - Find element by visual description
```
pc_ground description:"Compose button" app:"Chrome"
-> Returns: {x: 86, y: 223, confidence: 0.8, method: "full-screen"}
```

For overlapping UI panels (e.g., compose popup over inbox), use crop_box
to narrow the search area for dramatically better accuracy:
```
pc_ground description:"Send button" app:"Chrome" crop_box:[510, 168, 840, 390]
-> Returns: {x: 620, y: 350, confidence: 0.95, method: "crop-based"}
```

Then click at the returned coordinates:
```
pc_click x:86 y:223 app:"Chrome"
```

### pc_parse_screen - Detect all interactive elements
```
pc_parse_screen app:"Chrome"
-> Returns list of all detected UI elements with bounding boxes
```
Note: Full YOLO detection is not yet implemented. Use pc_find for
AX-based element search, and pc_ground for visual element finding.

## Rule 7: Handle Failures

If an action fails:
1. Call `pc_context` to see current state
2. Call `pc_annotate` for a labeled screenshot showing every interactive element with click coordinates
3. Call `pc_screenshot` for raw visual confirmation
4. Try `pc_ground` with a description of what you need to click
5. Try a different approach (different query, coordinates, etc.)

Don't retry the same thing 5 times. If pc_click fails, it already tried
AX-native, synthetic, AND VLM vision grounding. The element might not exist,
might be hidden, or might be blocked by a modal.

If `pc_screenshot` fails for a background app, the window may be minimized
or in another Space. YouxPC will attempt to capture it off-screen first. If
that fails, it will briefly activate the app to bring it on-screen. If the app
has no open windows at all, screenshot will return a specific error telling you.

## Rule 8: Web App Interaction (Chrome/Electron)

Chrome exposes most web elements as AXGroup -- `pc_find` may not locate
buttons or inputs by name. **Always prefer `dom_id` for web apps.**

Pattern:
```
pc_find query:"Send" role:AXButton app:"Chrome"  -> get dom_id from result
pc_click dom_id:":oq" app:"Chrome"               -> click by dom_id
```

`dom_id` clicks are the MOST reliable method for any web app button.

If `pc_find` returns nothing, use `pc_ground` with `crop_box` for
visual grounding.

For text input in web apps, click the field first (by dom_id or coordinates),
then use `pc_type`.

## Rule 9: Gmail / Email Pattern

Gmail's popup compose window does not reliably accept keyboard input from
synthetic events. Use URL-based compose instead:

```
Navigate to: https://mail.google.com/mail/?view=cm&fs=1&to=EMAIL&su=SUBJECT&body=BODY
```

Wait for the page to load, then find and click the Send button using dom_id.
The Send button's dom_id changes between sessions -- always `pc_find` it
first rather than hardcoding.

## Rule 10: Coordinate Mapping

Screenshots are downsampled to 1280px max width. Pixel coordinates in the
screenshot image are NOT the same as screen coordinates.

- Use `pc_ground` for visual-to-screen coordinate translation
- Use `pc_find` to get element positions (always in screen coordinates)
- The screenshot response includes `window_frame` with the actual screen
  position and size of the captured window

## Rule 11: Vision Grounding Best Practices

**ALWAYS use `crop_box` with `pc_ground`** when you know the approximate
area. It is 10x faster (250ms vs 3s) and much more accurate.

- `crop_box` format: `[x1, y1, x2, y2]` in logical screen points
- For overlapping UI (popups, dropdowns, compose windows), `crop_box` is
  ESSENTIAL to prevent the VLM from grounding to the wrong layer
- Get crop coordinates from `pc_find` element positions or `pc_state`
  window positions

## Rule 12: Wait Between Actions

Web apps need time to react to clicks. Always use `pc_wait` after clicking
buttons before proceeding:

```
pc_click query:"Submit" app:"Chrome"
pc_wait condition:"elementExists" value:"Success" app:"Chrome"
```

Common wait conditions:
- `urlContains` -- wait for navigation
- `titleContains` -- wait for page title change
- `elementExists` -- wait for an element to appear
- `elementGone` -- wait for a loading indicator to disappear

## Rule 13: Self-Learning Mode

YouxPC can learn workflows by watching the user perform them.

### How to use learning mode
1. User says they want to teach a workflow
2. Call `pc_learn_start` with a task_description
3. Tell the user to perform the task
4. User says they are done
5. Call `pc_learn_stop` to get the recorded actions
6. Analyze the actions: identify parameters (email addresses, names, URLs that should be substitutable)
7. Synthesize a recipe JSON from the actions (see Recipe JSON Schema below)
8. Verify the recipe works (see "Verifying recipes before saving" below)

### Synthesizing recipes from recordings
When you receive the action array from pc_learn_stop:
- Each `click` with an `element` context becomes a recipe step with a target Locator
- Use `dom_id` as the primary criterion if available (most stable for web apps)
- Use `role` + `computedNameContains` as secondary criteria
- Each `typeText` where the text looks like user-specific data (email, name, URL) becomes a `{{parameter}}`
- Each `keyPress` for Tab/Return becomes a `press` step
- Each `hotkey` becomes a `hotkey` step
- Each `appSwitch` becomes a `focus` step
- Infer `wait_after` conditions from timing gaps (>2s between actions suggests a page load)
- The recipe must use schema_version 2 and be compatible with pc_run

### Recipe JSON Schema

Every recipe saved via `pc_recipe_save` must follow this exact structure.
Missing or misnamed fields will cause a decode error.

```json
{
  "schema_version": 2,
  "name": "my-recipe-name",
  "description": "What this recipe does",
  "app": "Google Chrome",
  "params": {
    "recipient": {
      "type": "string",
      "description": "Email address of recipient",
      "required": true
    }
  },
  "preconditions": {
    "app_running": "Google Chrome",
    "url_contains": "example.com"
  },
  "steps": [
    {
      "id": 1,
      "action": "click",
      "target": {
        "criteria": [{"attribute": "AXDOMIdentifier", "value": ":oq"}],
        "computedNameContains": "Compose"
      },
      "wait_after": {
        "condition": "elementExists",
        "value": "To recipients",
        "timeout": 5
      },
      "note": "Click the compose button"
    },
    {
      "id": 2,
      "action": "type",
      "target": {
        "criteria": [{"attribute": "AXRole", "value": "AXComboBox"}],
        "computedNameContains": "To recipients"
      },
      "params": {"text": "{{recipient}}"},
      "note": "Type recipient email"
    },
    {
      "id": 3,
      "action": "press",
      "params": {"key": "tab"},
      "note": "Confirm autocomplete and move to next field"
    },
    {
      "id": 4,
      "action": "wait",
      "params": {"condition": "elementExists", "value": "Subject", "timeout": "5"},
      "note": "Wait for subject field to be ready"
    },
    {
      "id": 5,
      "action": "hotkey",
      "params": {"keys": "cmd,return"},
      "note": "Send with Cmd+Return"
    },
    {
      "id": 6,
      "action": "wait",
      "params": {"condition": "elementGone", "value": "Send", "timeout": "10"},
      "on_failure": "skip",
      "note": "Verify send completed (optional)"
    }
  ],
  "on_failure": "stop"
}
```

**Required fields:**
- `schema_version` -- must be `2`
- `name` -- string, used as filename and recipe identifier
- `description` -- string, shown in `pc_recipes` listing
- `steps` -- array, at least one step

**Optional top-level fields:**
- `app` -- default app for all steps
- `params` -- parameter definitions (see below)
- `preconditions` -- conditions to check before running
- `on_failure` -- `"stop"` (default) or `"skip"`. No other values are valid.

**Step fields:**
- `id` (required) -- integer, sequential starting from 1
- `action` (required) -- one of: `click`, `type`, `press`, `hotkey`, `focus`, `scroll`, `wait`, `hover`, `long_press`, `drag`
- `target` (optional) -- Locator object for finding the element to act on
- `params` (optional) -- action-specific parameters (see below). All values are **strings**.
- `wait_after` (optional) -- condition to wait for after this step completes
- `note` (optional) -- human-readable description of what this step does
- `on_failure` (optional) -- `"stop"` or `"skip"` (overrides recipe-level setting)

**Action params by type:**

| Action | Required params | Optional params |
|--------|----------------|-----------------|
| `click` | (none -- use `target`) | `x`, `y`, `button` (left/right/middle), `count` (2=double, 3=triple), `query` |
| `type` | `text` | `into`, `clear` ("true"), `app` |
| `press` | `key` | `modifiers` (comma-separated: cmd,shift,option,control), `app` |
| `hotkey` | `keys` (comma-separated: cmd,return) | `app` |
| `focus` | `app` | `window` |
| `scroll` | `direction` (up/down/left/right) | `amount`, `x`, `y`, `app` |
| `wait` | `condition` | `value`, `timeout` (seconds as string, default "10") |
| `hover` | (none -- use `target`) | `x`, `y`, `query`, `app` |
| `long_press` | (none -- use `target`) | `x`, `y`, `duration`, `button`, `query`, `app` |
| `drag` | `to_x`, `to_y` | `from_x`, `from_y`, `duration`, `hold_duration`, `query`, `app` |

Key names for `press`: return, tab, escape, space, delete, up, down, left, right, f1-f12.

**Important:** The `wait` action is different from `wait_after`. A `wait` step is
a standalone polling action with params like `{"condition": "elementExists", "value": "...", "timeout": "5"}`.
Note that `timeout` is a **string** (all step params are strings). `wait_after` is a
structured object on any step with `timeout` as a **number**. See the bundled
`slack-send` recipe for an example using both.

**Target (Locator) fields:**
- `criteria` -- array of `{"attribute": "...", "value": "..."}` objects. Common attributes:
  - `AXRole` -- element type (AXButton, AXTextField, AXTextArea, AXComboBox, AXLink, AXStaticText)
  - `AXDOMIdentifier` -- DOM id for web apps (most reliable for Chrome/Electron)
- `computedNameContains` -- string, matches element name/title/description (most useful field)
- `matchAll` -- boolean, whether all criteria must match (default: true)

**wait_after fields:**
- `condition` -- one of: `elementExists`, `elementGone`, `urlContains`, `titleContains`, `urlChanged`, `titleChanged`, `delay`
- `value` -- string to match against (not needed for `delay`, `urlChanged`, or `titleChanged`)
- `target` -- optional Locator; if `value` is nil, falls back to `target.computedNameContains`
- `timeout` -- number (seconds, default: 10). For `delay`, this is the sleep duration.

The same conditions work for standalone `wait` steps (pass as `params.condition`).

**Param definitions** (top-level `params` object):
- Each key is the parameter name
- `type` (required) -- `"string"`
- `description` (required) -- what this parameter is for
- `required` (optional) -- boolean

Use `{{param_name}}` in step params to substitute recipe parameters at runtime.

### Verifying recipes before saving

**Always test a recipe before considering it done.** This applies whether the recipe
came from self-learning mode or was authored from scratch.

1. Save the recipe with `pc_recipe_save`
2. Ask the user for safe test parameters (especially for recipes that send messages,
   emails, or modify files -- you don't want to send a real email during testing)
3. Run with `pc_run` using the test parameters
4. If the run fails: `pc_recipe_delete`, fix the JSON, go back to step 1
5. Repeat until the recipe runs successfully end-to-end
6. Tell the user the recipe is verified and ready

**Do not skip verification.** A recipe that fails on first use is worse than no
recipe at all.

### Requirements
- Input Monitoring permission required (separate from Accessibility)
- Only records between pc_learn_start and pc_learn_stop (no background monitoring)
- Password fields are automatically redacted
- Recordings are ephemeral (in memory only, never written to disk)
- Do not call pc_run while pc_learn is active (synthetic events would be re-recorded)

## Tool Reference

| Tool | Purpose | Needs Focus? |
|------|---------|-------------|
| pc_context | Where am I? URL, focused element, actions | No |
| pc_state | All running apps and windows | No |
| pc_find | Find elements by text, role, DOM id | No |
| pc_read | Read text content from screen | No |
| pc_inspect | Full element metadata | No |
| pc_element_at | What's at these coordinates? | No |
| pc_screenshot | Visual capture for debugging | No |
| pc_annotate | Labeled screenshot with click coordinates | No |
| pc_click | Click element or coordinates | Auto |
| pc_type | Type text, optionally into a field | Auto |
| pc_hover | Move cursor to trigger tooltips/hover effects | Yes - use `app` |
| pc_long_press | Press and hold for context menus | Yes - use `app` |
| pc_drag | Drag between points or elements | Yes - use `app` |
| pc_press | Press single key | Yes - use `app` |
| pc_hotkey | Key combo (cmd+s, etc.) | Yes - use `app` |
| pc_scroll | Scroll content | Yes - use `app` |
| pc_focus | Bring app to front | N/A |
| pc_window | Window management | No |
| pc_wait | Wait for condition | No |
| pc_recipes | List recipes | No |
| pc_run | Execute recipe | Auto |
| pc_recipe_show | View recipe details | No |
| pc_recipe_save | Save new recipe | No |
| pc_recipe_delete | Delete recipe | No |
| pc_parse_screen | Detect ALL UI elements via vision | No |
| pc_ground | Find element coordinates via VLM | No |
| pc_learn_start | Start observing user actions for learning | No |
| pc_learn_stop | Stop observing and return recorded actions | No |
| pc_learn_status | Check learning mode status | No |
