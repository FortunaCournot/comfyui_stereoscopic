---
name: "solve"
description: "Continue solution planning for a numbered workspace quickissue from copilot/quickissues"
argument-hint: "Issue number, for example: 1"
agent: "Plan"
Continue the solution planning for workspace issue `${input:issueNumber:Enter the issue number, for example 1}`.

- Requirements:
- Search `../copilot/quickissues` for a file whose name starts with the exact numeric prefix `<issueNumber>_`.
- If no matching file exists, stop and report that the issue number was not found. Suggest running `/issues`.
- Read the matching issue file completely before planning.
- Use the issue file as the primary problem statement.
- Gather only the additional code context that is necessary to continue planning the solution.
- Do not implement code changes unless the user explicitly asks for implementation.
- Respond in the user's current chat language unless they asked for another language.

Output format:
1. Issue
2. Relevant Code Areas
3. Likely Causes or Constraints
4. Proposed Next Steps
