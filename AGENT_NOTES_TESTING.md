# Agent notes: Testing pitfalls (Windows / portable)

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

(These notes exist so the agent/user avoids repeating the same environment setup mistakes.)
