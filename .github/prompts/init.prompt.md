---
name: "init"
description: "One-time repository initialization for the agent: import repo-scoped memories, register workspace prompts/instructions, and apply local defaults so the agent finds repo-based rules and prompts." 
agent: "agent"
---
Run this prompt once after a fresh checkout to prepare this repository for the VS Code Agent and other developers.

Goals:
- Ensure repository-scoped memos and rules are discoverable by the agent (convert to prompt/instruction files where appropriate).
- Ensure the local test folder `.test/` is present and ignored by git.
- Offer to commit the generated files (only after explicit confirmation).

Procedure (automated, with confirmations):
1. Scan the repository for these source locations:
   - `.github/memories/` — repo-scoped memos (human-readable guidance)
   - `.github/prompts/` — existing prompts (do not overwrite without confirmation)
   - `.github/instructions/` — workspace instructions (create if missing)
2. For each file found in `.github/memories/*.md` do:
   - Ask the user: "Import `FILENAME` as (p)rompt, (i)nstruction, (n)one?" Default to `(p)` for short guidance files and `(i)` for code-style or policy files.
   - If the user chooses `(p)`, create `.github/prompts/<basename>.prompt.md` with YAML frontmatter:
     ```yaml
     ---
     name: "<short name>"
     description: "Imported from .github/memories/<basename>.md"
     agent: "agent"
     ---
     <file body>
     ```
   - If the user chooses `(i)`, create `.github/instructions/<basename>.instructions.md` with YAML frontmatter:
     ```yaml
     ---
     description: "Repository instruction imported from .github/memories/<basename>.md"
     applyTo: "**/*"
     ---
     <file body>
     ```
   - If the target file already exists, show a diff and ask to (o)verwrite, (s)kip, or (e)dit.

3. Ensure `.test/` directory exists and is listed in `.gitignore`. If missing, create `.test/` and append `.test/` to `.gitignore`.

4. After all files are processed, ask: "Create a single commit with the new files?" If yes, run `git add` and `git commit -m "chore(init): register repo memories as prompts/instructions"`.

5. Final verification (automated):
   - Run the prompt discovery check and list `.github/prompts/*.prompt.md` and `.github/instructions/*.instructions.md` so the user can verify.

Notes and safety:
- This prompt will never push to remote; commits are local and require your confirmation.
- For ambiguous files, prefer creating an `instructions` file so the agent will load rules automatically.
- If you prefer a fully automated import without per-file prompts, rerun this prompt with the argument `auto=true`.

Example Git Bash commands (for PowerShell users):
```bash
# Run this prompt in VS Code Chat by selecting `/init` or run locally to inspect files:
# Convert memories to prompts (example script - DO NOT RUN without review):
for f in .github/memories/*.md; do
  base=$(basename "$f" .md)
  cp "$f" ".github/prompts/${base}.prompt.md"
done
```

Run `/init` now to start. The agent will prompt you for each conversion step and for final commit confirmation.
