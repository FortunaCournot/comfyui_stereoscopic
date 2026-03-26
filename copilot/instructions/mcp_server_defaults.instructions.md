---
applyTo: "**"
---

# MCP Server Defaults

When calling tools from the MCP server `my-mcp-server-258d3a2d` (https://api.githubcopilot.com/mcp/):

- **owner/user/repo** MUST be determined dynamically by running:
  `git -C <WORKSPACE_ROOT> remote get-url origin`
  and parsing the result:
  - HTTPS format: `https://github.com/<owner>/<repo>.git`
  - SSH format: `git@github.com:<owner>/<repo>.git`
- Cache the result per session — query exactly once, reuse for all subsequent tool calls.
- Never hard-code owner/user/repo values.
- Automatically fill `owner`, `user`, and `repo` parameters without asking the user.
