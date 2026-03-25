---
name: "issues"
description: "List numbered workspace issue files from .github/issues and summarize their current status"
agent: "agent"
---
List all open workspace issues stored in [../issues](../issues/).

Requirements:
- Only include files whose names start with a numeric prefix followed by `_`, such as `1_forward_progress_display.md`.
- Sort the result by the numeric prefix in ascending order.
- Read each matching issue file and extract the issue number, the issue title, and the current status.
- If a status line is missing, report the status as `Unknown`.
- Keep the response concise.
- Respond in the user's current chat language unless they asked for another language.

Output format:
`<number> - <title> - <status>`

If no numbered issue files exist, say that no workspace issues are currently tracked in [../issues](../issues/).
