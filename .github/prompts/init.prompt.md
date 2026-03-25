name: "init"
description: "One-time repository initialization verifier: check that repo-scoped prompts/instructions and local defaults are present. This prompt will NOT create or commit prompt/instruction files." 
agent: "agent"
---
Run this prompt once after a fresh checkout to verify that this repository is prepared for the VS Code Agent and other developers.

Goals:
- Verify that repository-scoped prompts exist under `.github/prompts/` and workspace instructions under `.github/instructions/`.
- Ensure the local test folder `.test/` exists and is listed in `.gitignore`.
- Do not create or commit prompt/instruction files; these must be created and committed separately (for example, via the `import_memories.sh` script run by a maintainer).

What this prompt does:
1. Lists `.github/prompts/` and `.github/instructions/` and reports any missing entries referenced in `.github/memories/`.
2. Ensures `.test/` exists and that `.gitignore` contains `.test/`; if `.test/` is missing, it will offer to create it locally but will not commit `.gitignore` changes.
4. Reads `.github/memories/` and lists each memory file found. For each memory file the prompt will report whether a corresponding prompt/instruction/issue file exists in the repository and will list any missing conversions. This is a verification step only — the prompt will not create or commit files.
3. Provides a summary and actionable next steps (for example, run `./.github/scripts/import_memories.sh` and commit the resulting files) but will not perform creation or commits itself.

Notes:
- If you want an automated import, run `./.github/scripts/import_memories.sh` as a maintainer and commit the generated files before running `/init` in other developer environments.
- This prompt intentionally avoids creating or committing repository files to keep initialization safe and reviewable.

Language preference (user-scoped):
- This prompt will ask whether you want to create a user-scoped memory recording your preferred language for agent interactions (for example, `German`). If you choose to create it, the prompt will offer instructions to create `/memories/preferred_language.md` locally; it will not commit or push that file.
- Repository maintainers may prefer that user-scoped memories are created by each developer locally rather than committed to the repository.

If you (the current user) want me to create a local user-scoped memory now, run the `/init create-language-memory` action or create `/memories/preferred_language.md` manually with your preference.

Verification outcome:
- After running `/init`, you will receive a report listing:
	- All files under `.github/memories/`.
	- Which of those are represented under `.github/prompts/`, `.github/instructions/` or `.github/issues/`.
	- Any missing items that a maintainer should import and commit (suggested `./.github/scripts/import_memories.sh` usage).
