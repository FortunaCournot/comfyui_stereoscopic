Repository Rules and Conventions
================================

This file records the repository-scoped rules derived from the session plan and workspace prompts. These are intended to be versioned and visible to all contributors.

1) Workspace Issues
- Versioned "Quick-Issues" are stored under `.github/issues/` as repository files and committed. They are intended for lightweight, repo-visible tracking of work items that the agent can reference.

2) Numbering
- Quick-Issues stored under `.github/issues/` SHOULD have filenames that begin with a decimal number and an underscore, without leading zeros (e.g. `1_forward_progress_display.md`, `2_another_issue.md`).
- Clarification: This numbering rule applies only to Quick-Issues filenames in `.github/issues/`. It does NOT apply to GitHub-managed Issues (the issue tracker) or other unrelated files.

3) Language of Issue Files
- Files under `.github/issues/` (Quick-Issues) SHOULD be written in English so that automated solvers and external contributors can process them consistently.

4) Completeness
- Issue files must be sufficiently self-contained so that the `solve` prompt can continue planning work for the issue number without requiring additional explanation.

5) Prompts
- The repository MUST provide workspace prompts `issues` and `solve` under `.github/prompts/`. The `solve` prompt accepts an issue number and initiates planning for that file.

6) User Interface vs. Content
- Agent interaction language (the language used by the agent to converse with a developer) may differ from the language of repository content. The agent's UI language for a given developer is controlled by a user-scoped memory (for example, `/memories/preferred_language.md`) and should be honored when present.

7) Fallback behaviour for `solve`
- If `solve` is invoked with an unknown issue number, it should respond with a clear, targeted message asking for clarification rather than searching arbitrarily.

8) Purpose of `/memories/repo/`
- The `/memories/repo/` folder is intended for non-versioned working notes, diagnostics, and knowledge that do not belong in `.github/issues/`.

9) Import convention
- When converting human-maintained repository memories into versioned prompts/instructions, prefer creating an `instructions` file for entries that read like policies or rules so they are applied automatically.

Notes
- These repository-scoped memories are the canonical, versioned record. Individual developers may keep local user-scoped memories for personal preferences (language, editor, shell) under `/memories/` — these should not be committed to the repository unless explicitly desired.

Repository commit rule
- Repository-scoped memories that are intended as the canonical, versioned record (for example the rules in this file, workspace prompts, and `.github/issues/` Quick-Issues) SHOULD be created and committed into the repository so they are visible to all contributors and to automation that depends on them. The repository policy is: when a memory is intended to be repo-scoped, it belongs under `.github/memories/`, `.github/prompts/`, `.github/instructions/` or `.github/issues/` and must be added and committed by a maintainer during normal change review.
