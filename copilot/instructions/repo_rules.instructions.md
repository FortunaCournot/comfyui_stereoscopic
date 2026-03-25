---
description: "Repository instruction imported from copilot/memories/repo_rules.md"
applyTo: "**/*"
---

Repository Rules and Conventions
================================

This file records the repository-scoped rules derived from the session plan and workspace prompts. These are intended to be versioned and visible to all contributors.

1) Workspace Issues
-- Versioned "Quick-Issues" are stored under `copilot/quickissues/` as repository files and committed. They are intended for lightweight, repo-visible tracking of work items that the agent can reference.

2) Numbering
-- Quick-Issues stored under `copilot/quickissues/` SHOULD have filenames that begin with a decimal number and an underscore, without leading zeros (e.g. `1_forward_progress_display.md`, `2_another_issue.md`).
 - Clarification: This numbering rule applies only to Quick-Issues filenames in `copilot/quickissues/`. It does NOT apply to GitHub-managed Issues (the issue tracker) or other unrelated files.

3) Language of Issue Files
-- Files under `copilot/quickissues/` (Quick-Issues) SHOULD be written in English so that automated solvers and external contributors can process them consistently.

4) Completeness
- Issue files must be sufficiently self-contained so that the `solve` prompt can continue planning work for the issue number without requiring additional explanation.

5) Prompts
- The repository MUST provide workspace prompts `issues` and `solve` under `copilot/prompts/`. The `solve` prompt accepts an issue number and initiates planning for that file.

6) User Interface vs. Content
- Agent interaction language (the language used by the agent to converse with a developer) may differ from the language of repository content. The agent's UI language for a given developer is controlled by a user-scoped memory (for example, `/memories/preferred_language.md`) and should be honored when present.

7) Fallback behaviour for `solve`
- If `solve` is invoked with an unknown issue number, it should respond with a clear, targeted message asking for clarification rather than searching arbitrarily.

8) Purpose of `/memories/repo/`
- The `/memories/repo/` folder is intended for non-versioned working notes, diagnostics, and knowledge that do not belong in `copilot/quickissues/`.

9) Import convention
- When converting human-maintained repository memories into versioned prompts/instructions, prefer creating an `instructions` file for entries that read like policies or rules so they are applied automatically.

Notes
- These repository-scoped memories are the canonical, versioned record and MUST be stored under `copilot/memories/` in this repository and committed so they are visible to contributors and automation.
- Individual developers may keep local, user-scoped memories for personal preferences (language, editor, shell) outside the repository (for example in a local `/memories/` or session memory). User-scoped memories MUST NOT be added or committed to the repository unless there is an explicit, reviewed justification for doing so.

Repository commit rule
- Repository-scoped memories that are intended as the canonical, versioned record (for example the rules in this file, workspace prompts, and Quick-Issues) SHOULD be created and committed into the repository so they are visible to all contributors and to automation that depends on them. The repository policy is: when a memory is intended to be repo-scoped, it belongs under `copilot/memories/`, `copilot/prompts/`, `copilot/instructions/` or `copilot/quickissues/` and must be added and committed by a maintainer during normal change review.

10) Policy: Repository‑Scope memories
- Repository‑scoped memories MUST be stored as local, versioned files under `copilot/memories/` in this repository.
- Do NOT create canonical repository‑scoped memories as global Agent memories outside the repository (for example under an external `/memories/` path that is not committed in the repo).
- If a global copy exists, replace it with a repo‑local file in `copilot/memories/` and add a pointer from the global note to the committed repo file; remove or deactivate the global copy to avoid divergence.
- Rationale: local, versioned memories enable review, history, and CI automation; global copies cause inconsistencies and cannot be reviewed through normal code review.
