Agent notes: Testing pitfalls (Windows / portable)
===============================================

This file is a repository-scoped copy of `AGENT_NOTES_TESTING.md` so the notes are versioned and visible to maintainers.

## Embedded Python location (portable ComfyUI)
ComfyUI portable ships its own Python interpreter (useful when `python` is not on PATH, or when you need the exact environment ComfyUI uses).

- Workspace-relative: `../../python_embeded/python.exe` (from `ComfyUI/custom_nodes/comfyui_stereoscopic`)
- Example absolute path (your machine): `e:\SD\vrweare\ComfyUI_windows_portable\python_embeded\python.exe`

Example compile check:
- `& "e:\SD\vrweare\ComfyUI_windows_portable\python_embeded\python.exe" -m py_compile "api/python/workflow/get_pose.py"`

## What happened (repro)
When running tests from `custom_nodes/comfyui_stereoscopic` on Windows, two recurring issues show up:

1) **Wrong interpreter / missing `pytest`**
- `pytest` was not on `PATH`, and `python` command was not available in that PowerShell session.
- The correct way in this repo is to call the workspace venv explicitly:
  - `& .\.venv\Scripts\python.exe -m pytest -q`

2) **Tests require ComfyUI + heavy deps**
- `tests/conftest.py` imports `folder_paths` (a ComfyUI module). That import fails if you run pytest in an environment that does not have ComfyUI on `sys.path`.
- `tests/test_triton.py` imports `torch`. If `torch` is not installed in the environment you use to run tests, pytest will fail already during collection.

## Fast preflight (recommended)
Run these before attempting pytest:

- Check interpreter:
  - `& .\.venv\Scripts\python.exe -c "import sys; print(sys.executable)"`
- Check pytest:
  - `& .\.venv\Scripts\python.exe -m pytest --version`
- Check ComfyUI module availability:
  - `& .\.venv\Scripts\python.exe -c "import folder_paths"`
- Check torch availability (if you intend to run the full suite):
  - `& .\.venv\Scripts\python.exe -c "import torch; print(torch.__version__)"`

## Practical guidance
- If you only need a **smoke-test** for FS status generation, run:
  - `& .\.venv\Scripts\python.exe .\api\compute_fs_status.py`
- If you want to run pytest successfully, you typically need:
  - to run in the **same Python environment** as ComfyUI (where `folder_paths` is importable), and
  - `torch` installed in that same environment.

## Bash on Windows (avoid WSL trap)
On this machine, `bash` resolves to `C:\Windows\System32\bash.exe` first, which is the WSL launcher.
If WSL has no distro installed, any attempt like `bash -n ...` fails with the “no installed distributions” message.

Use Git for Windows’ bash instead:
- `C:\Program Files\Git\bin\bash.exe`

Example syntax-check for scripts:
- `& "C:\Program Files\Git\bin\bash.exe" -n "api/tasks/workflow-v2v-transform.sh"`

## Task JSON parsing (trailing commas)
Some task definition files under `user/default/comfyui_stereoscopic/tasks/*.json` may contain **trailing commas**.

In this repo, many settings (including `override_reference_path`) are extracted via `grep`/`sed` patterns in the shell scripts rather than strict JSON parsing, so trailing commas are typically tolerated.

Guideline for debugging:
- Don’t assume “invalid JSON” is the root cause unless a *real* JSON parser is involved in that path.
- Verify effective values by checking whether the corresponding `grep -oE '"key"\s*:\s*"..."'` match triggers in the script logs.

## PowerShell quoting pitfalls (python -c / redirection)
When running one-off Python snippets via PowerShell, quoting can silently break the code you *think* you passed to `python -c`.

Observed failure modes (real examples from this workspace):
- **`<` inside the `-c` string**: PowerShell may interpret `<` as an operator/redirection-like token and throw a parser error (e.g. when printing text like `"<0.5"`).
  - Workaround: avoid `<`/`>` in the Python code string; print `lt0.5` instead.
- **F-strings / quotes getting mangled**: passing a multiline `-c` value that contains `"` and `{}` can end up with quotes stripped by Windows argument parsing, leading to syntax errors like `print(f{fn}: ...)`.
  - Workaround: prefer Python code that uses **only single quotes** when passed via `-c`.
  - Alternative: put the Python snippet into a **PowerShell here-string** (`$code=@' ... '@`) *and* ensure it contains no unescaped `"` sequences.
- **Control flow in a one-liner**: `python -c "...; while True: ..."` is fragile and often invalid unless you fully restructure it.
  - Workaround: use `for` loops (single-line friendly) or write a short temp `.py` script.

Reliable patterns:
- Prefer `get_pose.py --out-file ...` over shell redirection (`>`), especially in PowerShell.
- For stats/analysis snippets:
  - Use `$code=@' ... '@; & $py -c $code ...` and keep Python strings single-quoted.
- If the snippet grows beyond ~10 lines: write `tmp_stats.py` to `%TEMP%` and run it.

## batch_tasks.sh: is_disabled() perceived slowness (parked)
User observation: batch startup feels slow with dozens of task folders.

Current assessment (no code changes requested):
- `is_disabled()` itself is lightweight logically, but it spawns external processes per call (`awk`, `tr`, plus `sed` per value) and is called twice per task folder; on Git Bash/Windows process startup overhead can be noticeable.
- Likely larger contributors are filesystem scans like `find ... | wc -l` per folder and the `find ... -print0` loops.

Suggested next-day verification (no code changes):
- Temporarily rename `user/default/comfyui_stereoscopic/unused.properties` and compare startup speed; if faster, `is_disabled()` cost is material.

## Shell optimization preference
- In shell scripts for this repo, avoid `sed` where plain shell parameter expansion can do the same job safely.
- Typical examples: trimming whitespace, extracting path parts, removing prefixes/suffixes, and simple character replacement.
- Keep `sed` only where the transformation is genuinely regex-heavy or would become less readable in pure shell.

(These notes exist so the agent/user avoids repeating the same environment setup mistakes.)
