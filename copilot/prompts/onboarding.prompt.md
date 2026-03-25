---
name: "onboarding"
description: "One-time repository onboarding verifier: check that repo-scoped prompts/instructions and local defaults are present. This prompt will automatically import repository-scoped memories into `copilot/prompts/` and `copilot/instructions/` locally. On Windows the prompt will also create a local junction `.github/prompts` -> `copilot/prompts` if it is missing (local change only)."
agent: "agent"
---
Run this prompt once after a fresh checkout to verify that this repository is prepared for the VS Code Agent and other developers.

Goals:
- Verify that repository-scoped prompts exist under `copilot/prompts/` and workspace instructions under `copilot/instructions/`.
- Ensure the local test folder `.test/` exists and is listed in `.gitignore`.
- Automatically import `copilot/memories/` into `copilot/prompts/` and `copilot/instructions/` locally; the prompt will not commit or push generated files.

What this prompt does:
1. On Windows: check whether `.github/prompts` exists and points to `copilot/prompts`. If `.github/prompts` is missing or not a junction, the prompt will run the helper script `copilot/scripts/create_junction.ps1` to create a local junction `.github/prompts` -> `copilot/prompts`, removing an empty `.github/prompts` folder first if necessary. The prompt will report the commands it ran. This operation is local and will not commit or push changes unless you explicitly request `--commit`.
2. Lists `copilot/prompts/` and `copilot/instructions/` and reports any missing entries referenced in `copilot/memories/`.
3. Ensures `.test/` exists and that `.gitignore` contains `.test/`; if `.test/` is missing, it will offer to create it locally but will not commit `.gitignore` changes.
4. Reads `copilot/memories/` and lists each memory file found. For each memory file the prompt will report whether a corresponding prompt/instruction/issue file exists in the repository and will list any missing conversions. This is a verification step only — the prompt will not create or commit files.
5. Provides a summary and actionable next steps. The prompt automatically runs the import script to generate prompt/instruction files locally; it will not commit or push generated files.
6. Reports the currently configured preferred language if a user-scoped memory exists, and shows instructions to set or change it via agent actions. If no preference is set, it will report `Preferred_Language: None` and show instructions to create one. Details:
- If a language memory exists, the prompt will report the detected language using an English label (for example: "Preferred_Language: German") and show concise instructions how to change it via an agent action (see below).
- If no language memory exists, the prompt will show the options to create one locally via the `/onboarding create-language-memory` action and will show the exact file contents to write. The prompt will not commit or push any files.

Behavior when run:
- The prompt MUST always output a single line exactly in the form `Preferred_Language: <Language>`.
  - If no language is configured, the value MUST be `None`, e.g. `Preferred_Language: None`.
- Immediately after that line the prompt MUST display these three one-line commands (exact text) that the user can send to change the preference:
  - `SetPreferredLanguage <Language>`
  - `CreatePreferredLanguage <Language>`
  - `ClearPreferredLanguage`

Examples the agent should always show (replace `<Language>` as appropriate):
```
Preferred_Language: German
SetPreferredLanguage Spanish
CreatePreferredLanguage Spanish
ClearPreferredLanguage
```
If no language is set the example should use `None`:
```
Preferred_Language: None
To change enter one of the following commands:
> SetPreferredLanguage German
> OrCreatePreferredLanguage German
> ClearPreferredLanguage
```


Notes:
- The prompt automatically imports repository-scoped memories locally; it will not commit or push generated files. Review generated files under `copilot/prompts/` and `copilot/instructions/` before committing.
 - This prompt still avoids making repository commits by default to keep initialization safe and reviewable.


Junction management (local only):
- Create local junction: If you want the agent to create a local junction so that `.github/prompts` points to `copilot/prompts`, send the action `/onboarding create-junction`.
  - This will attempt to create the junction locally on Windows using `cmd /c mklink /J .github\prompts copilot\prompts` or PowerShell `New-Item -ItemType Junction -Path .github\prompts -Target .\copilot\prompts` if supported. The agent will remove an empty `.github/prompts` folder first if necessary. The agent will not push or commit changes by default.
  - If you prefer the agent to also update `.gitignore` and remove any previously tracked `.github/prompts` entries from the index, use `/onboarding create-junction --commit` and the agent will run `git add .gitignore; git rm -r --cached .github/prompts || true; git commit -m "Ignore local junction .github/prompts"` locally.

- Remove local junction: Send `/onboarding remove-junction` to remove the `.github/prompts` junction (this deletes the junction entry only; the `copilot/prompts` folder is left intact).

Notes:
- These actions are local developer conveniences and will not create or commit repository-scoped prompt files unless you explicitly ask for the `--commit` variant. The agent will report what it changed and show the exact commands it ran.

Simple user prompt examples:
name: "onboarding"
description: "One-time repository onboarding verifier: check that repo-scoped prompts/instructions and local defaults are present. This prompt will automatically import repository-scoped memories into copilot/prompts and copilot/instructions locally and will NOT commit generated files."
agent: "agent"
---
Run this prompt once after a fresh checkout to verify that this repository is prepared for the VS Code Agent and other developers.

Goals:
- Verify that repository-scoped prompts exist under `copilot/prompts/` and workspace instructions under `copilot/instructions/`.
- Ensure the local test folder `.test/` exists and is listed in `.gitignore`.
- Automatically import `copilot/memories/` into `copilot/prompts/` and `copilot/instructions/` locally; the prompt will not commit or push generated files.

What this prompt does:
1. Lists `copilot/prompts/` and `copilot/instructions/` and reports any missing entries referenced in `copilot/memories/`.
2. Ensures `.test/` exists and that `.gitignore` contains `.test/`; if `.test/` is missing, it will offer to create it locally but will not commit `.gitignore` changes.
3. Reads `copilot/memories/` and lists each memory file found. For each memory file the prompt will report whether a corresponding prompt/instruction/issue file exists in the repository and will list any missing conversions. This is a verification step only — the prompt will not create or commit files.
4. Provides a summary and actionable next steps. The prompt automatically runs the import script to generate prompt/instruction files locally; it will not commit or push generated files.

Notes:
- The prompt automatically imports repository-scoped memories locally; it will not commit or push generated files. Review generated files under `copilot/prompts/` and `copilot/instructions/` before committing.
 - This prompt still avoids making repository commits by default to keep initialization safe and reviewable.

Language preference (user-scoped):
- This prompt will ask whether you want to create a user-scoped memory recording your preferred language for agent interactions (for example, `German`). If you choose to create it, the prompt will offer instructions to create `/memories/preferred_language.md` locally; it will not commit or push that file.
- Repository maintainers may prefer that user-scoped memories are created by each developer locally rather than committed to the repository.

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
-- After running `/onboarding`, you will receive a report listing:
  - All files under `copilot/memories/`.
  - Which of those are represented under `copilot/prompts/`, `copilot/instructions/` or `copilot/quickissues/`.
  - Any missing items that a maintainer should import and commit (suggested `./copilot/scripts/import_memories.sh` usage).

- If a user language preference is present, the verifier will report it using the English label, for example:

  Preferred_Language: German  — Change with a prompt like: SetPreferredLanguage Spanish
