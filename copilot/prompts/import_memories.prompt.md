---
name: "import_memories"
description: "Run the import_memories script to regenerate local prompts/instructions without asking the user."
agent: "agent"
---

Run the repository import now. This prompt executes the import script non-interactively and reports its output.

Execution behaviour (agent MUST follow):
- On Windows (preferred): run `.venv\Scripts\python.exe copilot\scripts\import_memories.py` from the repository root.
- On Unix/macOS: run `./copilot/scripts/import_memories.sh` from the repository root.
- Do NOT prompt the user for confirmation or additional input; run the script and stream its stdout/stderr.
- Do NOT commit or push any generated files; generated outputs are local to `.copilot_local/` unless the user explicitly requests a commit.

After running, summarize:
- which files were created or updated under `.copilot_local/` (list paths),
- any changes written to the root `.gitignore`, and
- any errors encountered.

If the agent cannot run commands in the environment, report the exact command that the user should run locally and do not attempt further actions.
