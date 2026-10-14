# Security

YouxPC lets an AI agent read and operate apps on your Mac. Treat it as you would any tool with that reach.

## Reporting a problem

Please report security problems privately, through GitHub's "Report a vulnerability" button on this repository (Security tab), not in a public issue. Say what you did, what happened and what you expected. You will get a reply within a few days.

## What the safety features do

- **App policy.** By default the server refuses to read or act on password managers, Keychain Access, System Settings, system permission prompts, the login window, terminal emulators and the app that hosts the agent. `YOUXPC_ALLOW_APPS` turns this into a strict allowlist.
- **Terminal sessions.** Off unless you list approved commands. A listed command is started directly, with no shell, and keystrokes are delivered to that program only.
- **Never-press list.** `YOUXPC_NEVER_PRESS` stops presses on controls whose name contains one of your words.
- **Receipts.** Every tool call is written to `~/.youxpc/logs/receipts.jsonl`.
- **No network use** beyond loopback, and no telemetry.

## What they do not do

- They are not a sandbox. An agent that is allowed to use an app can do anything in that app that its controls allow.
- The never-press list guards against accidents. A form can still be submitted with Return from a text field, and a control with no accessible name cannot be matched.
- An approved terminal program can do whatever that program can do.
- Text on screen can contain instructions aimed at the agent. The server tells agents to treat screen text as data, but it cannot make a model obey that.
- macOS grants Accessibility and Screen Recording to the app that launches the server, not to `youxpc`. Anything else that app runs has the same access.

If you need a hard boundary, run the agent in a separate macOS user account or a virtual machine.
