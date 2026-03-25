Copilot content moved to `copilot/`
===============================

Repository maintainers: the repository-scoped Copilot prompts, memories and scripts were moved to `copilot/` at the repository root.

If you previously used files under `.github/prompts/`, `.github/memories/` or `.github/scripts/`, please update your local workflows and scripts to reference `copilot/` instead.

Temporary plan:
- For a safe migration we copied files into `copilot/` and updated internal references there. The original `.github/` copies may remain until maintainers confirm the migration and remove them.

To run the import script from the new location:

```bash
./copilot/scripts/import_memories.sh
```

If you are an automation author and need a backwards-compatible redirect, prefer updating the automation to use `copilot/` rather than relying on symlinks.
