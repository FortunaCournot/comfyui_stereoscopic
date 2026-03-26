MCP Server Defaults
===================

## my-mcp-server-258d3a2d (https://api.githubcopilot.com/mcp/)

- **owner/user/repo**: Dynamisch per `git -C <WORKSPACE_ROOT> remote get-url origin` ermitteln und aus der URL parsen.
  - HTTPS-Format: `https://github.com/<owner>/<repo>.git`
  - SSH-Format: `git@github.com:<owner>/<repo>.git`
- Den ermittelten owner/repo **pro Sitzung cachen** — nur einmal abfragen, danach den gecachten Wert wiederverwenden.
- Bei allen Tool-Aufrufen an diesen MCP-Server, die einen `owner`-, `user`- oder `repo`-Parameter benötigen, diesen Wert automatisch einsetzen ohne den User zu fragen.
