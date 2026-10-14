---
name: An app is listed wrongly or cannot be operated
about: The snapshot is empty or wrong, or a click or typing does not work in some app
labels: app-support
---

**App and version** (for example: Notes 4.11, Slack 4.41 from the App Store)

**macOS version**

**What you asked for and what happened**

**The snapshot** (run this and paste the output; remove anything private first)

```
youxpc mcp   # then call pc_snapshot app:"<App>" full:true from your agent
```

**The receipt lines for the failing calls** (`youxpc receipts --last 10`)
