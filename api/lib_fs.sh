#!/bin/sh
# Fast Filesystem helper library (Python-backed)
# Replaces slow `find | wc -l` calls with a small Python implementation
# using os.scandir() for efficiency. Falls back to `find` when no Python.

# relative or absolute path of ComfyUI folder in your ComfyUI_windows_portable
# Default: Executed in ComfyUI folder
# Determine script directory robustly (works when the file is sourced or executed)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
_COMFYUIPATH="$(realpath "$SCRIPT_DIR/../../..")"

# Use Systempath for python by default, but set it explictly for comfyui portable.
# Try to set PYTHON_BIN_PATH if not already set by caller scripts
if [ -z "${PYTHON_BIN_PATH:-}" ]; then
    # Prefer the node's embedded virtualenv (relative to this script), then other common locations
    if [ -x "${_COMFYUIPATH}/custom_nodes/comfyui_stereoscopic/.venv/Scripts/python.exe" ]; then
        PYTHON_BIN_PATH="${_COMFYUIPATH}/custom_nodes/comfyui_stereoscopic/.venv/Scripts/"
    elif [ -x "${_COMFYUIPATH}/python_embeded/python.exe" ]; then
        PYTHON_BIN_PATH="${_COMFYUIPATH}/python_embeded/"
    elif [ -x "${_COMFYUIPATH}/.venv/Scripts/python.exe" ]; then
        PYTHON_BIN_PATH="${_COMFYUIPATH}/.venv/Scripts/"
    else
        PYTHON_BIN_PATH=""
    fi
fi
export PYTHON_BIN_PATH
echo "LOG: PYTHON_BIN_PATH=\"${PYTHON_BIN_PATH}\""

# Resolve a PYTHON executable to use for internal Python calls
PYTHON=""
# If caller provided an absolute PYTHON path, keep it. Otherwise prefer explicit python.exe path.
if [ -n "${PYTHON:-}" ] && [ -x "${PYTHON}" ]; then
    :
elif [ -n "${PYTHON_BIN_PATH:-}" ] && [ -x "${PYTHON_BIN_PATH}python.exe" ]; then
    PYTHON="${PYTHON_BIN_PATH}python.exe"
elif command -v python >/dev/null 2>&1; then
    PYTHON=python
elif command -v python3 >/dev/null 2>&1; then
    PYTHON=python3
else
    PYTHON=""
fi
export PYTHON

if [ -n "$PYTHON" ]; then
    echo "LOG: PYTHON_RESOLVED=\"${PYTHON}\" PYTHON_BIN_PATH=\"${PYTHON_BIN_PATH}\""
else
    echo "LOG: PYTHON_RESOLVED=\"\" PYTHON_BIN_PATH=\"${PYTHON_BIN_PATH}\""
    echo "LOG: PYTHON_FALLBACK=\"using find-based fallback for counts\""
fi


_py_count() {
    dir="$1"; mode="$2"; shift 2
    # Call Python with script read from stdin; pass args after '-'
    "$PYTHON" - "$dir" "$mode" "$@" <<'PY'
import os,sys
def safe_int(x):
    try:
        return int(x)
    except Exception:
        return 0

d=sys.argv[1]
mode=sys.argv[2]
args=sys.argv[3:]
if not os.path.isdir(d):
    print(0); sys.exit(0)
cnt=0
try:
    it=os.scandir(d)
    if mode=='any':
        # count regular files that contain a dot (has an extension)
        cnt = sum(1 for e in it if e.is_file() and '.' in e.name)
    elif mode=='exts':
        exts=[a.lstrip('.').lower() for a in args]
        for e in it:
            if not e.is_file():
                continue
            nm=e.name.lower()
            for ex in exts:
                if nm.endswith('.'+ex):
                    cnt += 1
                    break
    elif mode=='dirs_prefix':
        pref=args[0] if args else ''
        cnt = sum(1 for e in it if e.is_dir() and e.name.startswith(pref))
    else:
        cnt = 0
except Exception:
    cnt = 0
print(cnt)
PY
}

count_files_any_ext() {
    dir="$1"
    _py_count "$dir" any
}

count_files_with_exts() {
    dir="$1"; shift || true
    _py_count "$dir" exts "$@"
}

count_dirs_with_prefix() {
    dir="$1"; pref="$2"
    _py_count "$dir" dirs_prefix "$pref"
}

# If no Python detected, provide a find-based fallback to preserve behavior
if [ -z "$PYTHON" ]; then
    count_files_any_ext() {
        dir="$1"
        if [ ! -d "$dir" ]; then
            echo 0; return
        fi
        find "$dir" -maxdepth 1 -type f -name '*.*' 2>/dev/null | wc -l
    }
    count_files_with_exts() {
        dir="$1"; shift || true
        if [ ! -d "$dir" ]; then
            echo 0; return
        fi
        total=0
        for ext in "$@"; do
            e="$ext"
            case "$e" in
                .* ) e="${e#*.}" ;;
            esac
            cnt=$(find "$dir" -maxdepth 1 -type f -iname "*.$e" 2>/dev/null | wc -l)
            total=$((total + cnt))
        done
        echo "$total"
    }
    count_dirs_with_prefix() {
        dir="$1"; prefix="$2"
        if [ ! -d "$dir" ]; then
            echo 0; return
        fi
        find "$dir" -maxdepth 1 -type d -name "${prefix}*" 2>/dev/null | wc -l
    }
fi

return 0
