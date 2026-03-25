name: "onboarding"
description: "One-time repository onboarding verifier: check that repo-scoped prompts/instructions and local defaults are present. This prompt will NOT create or commit prompt/instruction files."
agent: "agent"
---
Run this prompt once after a fresh checkout to verify that this repository is prepared for the VS Code Agent and other developers.

Goals:
- Verify that repository-scoped prompts exist under `copilot/prompts/` and workspace instructions under `copilot/instructions/`.
- Ensure the local test folder `.test/` exists and is listed in `.gitignore`.
- Do not create or commit prompt/instruction files; these must be created and committed separately (for example, via the `import_memories.sh` script run by a maintainer).

What this prompt does:
1. Lists `copilot/prompts/` and `copilot/instructions/` and reports any missing entries referenced in `copilot/memories/`.
2. Ensures `.test/` exists and that `.gitignore` contains `.test/`; if `.test/` is missing, it will offer to create it locally but will not commit `.gitignore` changes.
3. Reads `copilot/memories/` and lists each memory file found. For each memory file the prompt will report whether a corresponding prompt/instruction/issue file exists in the repository and will list any missing conversions. This is a verification step only — the prompt will not create or commit files.
4. Provides a summary and actionable next steps (for example, run `./copilot/scripts/import_memories.sh` and commit the resulting files) but will not perform creation or commits itself.

Notes:
- If you want an automated import, run `./copilot/scripts/import_memories.sh` as a maintainer and commit the generated files before running `/onboarding` in other developer environments.
- This prompt intentionally avoids creating or committing repository files to keep initialization safe and reviewable.

Language preference (user-scoped):
- This prompt will ask whether you want to create a user-scoped memory recording your preferred language for agent interactions (for example, `German`). If you choose to create it, the prompt will offer instructions to create `/memories/preferred_language.md` locally; it will not commit or push that file.

Language preference (user-scoped):
- Before prompting the user to create a language preference, this onboarding verifier will first check whether a user-scoped memory file `/memories/preferred_language.md` already exists for the current developer.
- If a language memory exists, the prompt will report the detected language using an English label (for example: "Preferred_Language: German") and show concise instructions how to change it via an agent action (see below).
- If no language memory exists, the prompt will offer the option to create one locally via the `/onboarding create-language-memory` action and will show the exact file contents to write. The prompt will not commit or push any files.

How to set, change, or clear your preferred language via the agent:
- You do not need to edit files yourself. Instead, send the agent one of the following actions (the agent will create/update/remove the local user-scoped memory on your behalf; the agent will not commit or push repository changes):

- Set or change language (example):

  /onboarding set-language German

- Create the language memory if missing (equivalent):

  /onboarding create-language-memory German

- Clear/remove the language preference:

  /onboarding clear-language

- After performing any of the above, the agent will report the currently configured preference using the English label `Preferred_Language:` (for example: `Preferred_Language: German`).

If you (the current user) want me to create or update the local user-scoped memory now, send `/onboarding set-language <Language>` or `/onboarding create-language-memory <Language>`.

Simple user prompt examples:
- Short command (recommended):

  SetPreferredLanguage German

- Natural language (works too):

  Please set my preferred language to German

- Clear preference:

  ClearPreferredLanguage

Notes:
- The slash actions also work (`/onboarding set-language German`, `/onboarding clear-language`). Use whichever form you prefer; the agent recognises these examples and will update your local user memory accordingly.

Verification outcome:
- After running `/onboarding`, you will receive a report listing:
  - All files under `copilot/memories/`.
  - Which of those are represented under `copilot/prompts/`, `copilot/instructions/` or `.github/issues/`.
  - Any missing items that a maintainer should import and commit (suggested `./copilot/scripts/import_memories.sh` usage).

- If a user language preference is present, the verifier will report it using the English label, for example:

  Preferred_Language: German  — Change with a prompt like: SetPreferredLanguage Spanish
