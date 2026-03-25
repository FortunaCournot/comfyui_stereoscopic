Session Memory Policy
=====================

Session memories (under `/memories/session/`) are intended for ephemeral, in-progress notes tied to a particular session or working draft. They MUST NOT be used to store repository-wide rules, policies, or cross-cutting conventions.

Rules:
- Only session- or task-specific notes belong in `/memories/session/` (e.g. short-lived plans, experiment notes, or in-progress checklists).
- Cross-cutting rules, repository policies, or any content that should be shared and version-controlled MUST be placed in repository-scoped memories under `.github/memories/` or as prompts/instructions under `.github/prompts/` or `.github/instructions/` and committed.
- The `plan.md` in `/memories/session/` may reference repository rules but must not be used as the canonical source for such rules.

Enforcement:
- The `init` prompt will verify that no repository-level rules are only present in `/memories/session/` and will list any such occurrences so a maintainer can promote them to `.github/memories/`.
