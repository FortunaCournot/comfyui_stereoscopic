# Agent notes: Testing pitfalls (Windows / portable)

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

## batch_tasks.sh: is_disabled() perceived slowness (parked)
User observation: batch startup feels slow with dozens of task folders.

Current assessment (no code changes requested):
- `is_disabled()` itself is lightweight logically, but it spawns external processes per call (`awk`, `tr`, plus `sed` per value) and is called twice per task folder; on Git Bash/Windows process startup overhead can be noticeable.
- Likely larger contributors are filesystem scans like `find ... | wc -l` per folder and the `find ... -print0` loops.

Suggested next-day verification (no code changes):
- Temporarily rename `user/default/comfyui_stereoscopic/unused.properties` and compare startup speed; if faster, `is_disabled()` cost is material.

(These notes exist so the agent/user avoids repeating the same environment setup mistakes.)
