# One agent driving several others

A lead agent with YouxPC can start other command-line agents in Terminal
windows, give each a task, read what they produce and close them when they are
done. It can do the same with Mac apps. This page says what works today, how to
set it up, and where it stops.

## What was tested

- Two `opencode` sessions were started side by side through `pc_terminal`.
  Each was sent a different prompt before either had answered. Each returned
  its own answer about three seconds later, with no cross-talk, and both
  windows were closed with one call.
- `opencode` was driven through its own interface: the model picker was
  opened with `/models`, searched, a model chosen, a prompt sent and the reply
  read back.
- A session survived a killed server: a new server process found it again and
  kept driving it.
- All of that ran with Terminal in the background. The lead agent's own app
  stayed in front and the pointer was not used.

Not tested: driving `claude` or `codex` this way (they were not on the approved
list), more than two sessions at once, and sessions that run for hours.

## Setup

Approve the commands the lead agent may start, in the MCP server's environment:

```
YOUXPC_TERMINAL_COMMANDS=opencode,claude,codex
```

Then the lead agent can do this:

```
pc_terminal action:"run"  command:"opencode" cwd:"/path/to/project-a"   -> session a1
pc_terminal action:"run"  command:"opencode" cwd:"/path/to/project-b"   -> session b2
pc_terminal action:"type" session:"a1" text:"Add input validation to the signup form" enter:true
pc_terminal action:"type" session:"b2" text:"Write tests for the billing module" enter:true
pc_terminal action:"read" session:"a1"
pc_terminal action:"read" session:"b2"
pc_terminal action:"close" all:true
```

Give each session its own working directory so the agents do not edit the same
files.

## Why this is safe to run in parallel

Keystrokes are posted to the Terminal process and reach only the session whose
window YouxPC has just selected and verified. They do not go to "whatever is in
front", so two sessions cannot receive each other's input and nothing can land
in an unrelated app. Input is refused when the approved program has exited or
has put a child process in the foreground.

The same holds for Mac apps operated through accessibility: pressing a button
or setting a text field does not need the app in front, so the lead agent can
work in several background apps in turn.

## Where it stops

- **Calls are sequential.** The server handles one tool call at a time. The
  lead agent interleaves: prompt A, prompt B, read A, read B. The workers run
  concurrently; the lead's attention does not.
- **One screen.** Anything that needs the real pointer or the app in front
  (canvas-style UI, Cmd shortcuts) is exclusive while it happens.
- **Reading is polling.** There is no notification when a worker finishes. The
  lead agent reads the session until the output shows it is done, which costs
  tokens. Keep `lines` small.
- **Terminal output is text on a grid.** Full-screen interfaces are readable
  but noisy, and anything scrolled out of the visible buffer is gone.
- **Approval is coarse.** An approved agent CLI can do whatever that CLI
  permits, including running shell commands. The allowlist controls what gets
  launched, not what the launched agent then does. Use each worker's own
  permission settings, give it a narrow working directory, and consider
  `YOUXPC_TERMINAL_SANDBOX=on`, which denies file writes outside the working
  directory and temp folders.
- **Worker output is untrusted.** A worker can be wrong, and text it prints
  could contain instructions. The lead agent should check results, not relay
  them.
- **Cost adds up.** Every worker spends its own tokens on its own account.

## Lead model strength

A strong model can plan the split, notice when a worker has stalled, and
recover. A small local model can follow the five-tool simple profile for one
app at a time, but coordinating several workers is a planning task; expect it
to need a strong lead. The benchmark in `bench/` measures single-agent tasks
only, so there are no numbers for orchestration yet.
