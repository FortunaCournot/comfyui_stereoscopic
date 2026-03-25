
Code style preference:
- All code comments, docstrings, and documentation should be written in English.
- New identifiers should also be English by default.
- Do not rename existing identifiers unless explicitly requested.

- In shell scripts, avoid sed when shell parameter expansion can express the same transformation clearly and safely.
- Issue files and issue tracker notes should also be written in English.
- Issue descriptions should be self-contained and high-quality so follow-up prompts like `/solve` can start planning without re-explaining the problem.

- Temporary test scripts must be created in a non-tracked test folder (e.g., `.test/`) and never placed in the repository top-level.

- When creating memories, always ask whether the scope should be `Repository` or `User` and record the chosen scope. Only create session (`/memories/session/`) memories when they are strictly temporary and required for the agent's immediate work.
