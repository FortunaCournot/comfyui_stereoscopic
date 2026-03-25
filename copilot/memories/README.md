Repository-scoped memories
=========================

This folder holds repository-scoped guidance and short notes intended to be visible and versioned with the project.

Purpose
-------
- Store repo-wide conventions, environment hints, and small policy notes.
- Serve as the single source of truth for local agent behaviour that should be shared with contributors.

How to make these discoverable to the VS Code Agent
---------------------------------------------------
The agent discovers workspace prompts and instructions in `copilot/prompts/` and `copilot/instructions/`.
To convert the files in this folder into prompt or instruction files you can:

- Run the import script (fully automatic):

```bash
./copilot/scripts/import_memories.sh
```

- Or use the `/onboarding` workspace prompt which wraps the same functionality (it can run in `auto=true` mode).

Notes
-----
- The import script uses heuristics to decide whether a memory should be an instruction (policy/style files) or a prompt (guidance). Review generated files under `copilot/prompts/` and `copilot/instructions/` before committing.
 - The script uses heuristics to decide whether a memory should be an instruction (policy/style files) or a prompt (guidance). Review generated files under `copilot/prompts/` and `copilot/instructions/` before committing.
