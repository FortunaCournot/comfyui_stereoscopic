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
# Only emit PYTHON-related logs when Python is not found (error case).

# Resolve a PYTHON executable to use for internal Python calls
PYTHON="${PYTHON_BIN_PATH}python.exe"
export PYTHON

if [ -z "$PYTHON" ]; then
    echo "LOG: ERROR=\"python not found; using find-based fallback for counts\"" >&2
fi

# --- Tracing helpers ---
# Minimal start/end trace to measure call durations (seconds, milliseconds when available)
_trace_start() {
    # try sub-second precision; fall back to integer seconds
    _TRACE_START=$(date +%s.%N 2>/dev/null || date +%s)
}

_trace_end() {
    func="$1"; shift || true
    params="$*"
    _TRACE_END=$(date +%s.%N 2>/dev/null || date +%s)
    # compute elapsed using awk for floating arithmetic
    elapsed=$(awk -v s="${_TRACE_START}" -v e="${_TRACE_END}" 'BEGIN{printf "%.3f", e - s}')
    # echo "LOG: TRACE=\"${func} params=[${params}] elapsed=${elapsed}s\"" >&2
}


_py_count() {
    dir="$1"; mode="$2"; shift 2
    # Optional debug instrumentation when FS_DEBUG=1 to separate Python startup vs scan time
    if [ "${FS_DEBUG:-0}" -eq 1 ]; then
        PY_STDERR_TMP=$(mktemp 2>/dev/null || echo /tmp/libfs_dbg.$$)
        PY_CALL_START=$(date +%s.%N 2>/dev/null || date +%s)
        pyout=$("$PYTHON" - "$dir" "$mode" "$@" <<'PY' 2>"$PY_STDERR_TMP"
import os,sys,time
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
scan_t0=time.time()
try:
    it=os.scandir(d)
    if mode=='any':
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
scan_t1=time.time()
print(cnt)
sys.stderr.write(f"LOG: PY_SCAN=\"{(scan_t1-scan_t0):.6f}s\"\n")
PY
        )
        # forward python stderr to our stderr and remove tmp
        [ -f "$PY_STDERR_TMP" ] && cat "$PY_STDERR_TMP" >&2 && rm -f "$PY_STDERR_TMP"
        PY_CALL_END=$(date +%s.%N 2>/dev/null || date +%s)
        # compute python process elapsed
        py_elapsed=$(awk -v s="$PY_CALL_START" -v e="$PY_CALL_END" 'BEGIN{printf "%.6f", e - s}')
        # echo "LOG: PY_CALL=\"${py_elapsed}s\"" >&2
        echo "$pyout"
        return
    fi
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
    _trace_start
    dir="$1"
    result=$(_py_count "$dir" any)
    echo "$result"
    _trace_end count_files_any_ext "$dir"
}

count_files_with_exts() {
    _trace_start
    dir="$1"; shift || true
    result=$(_py_count "$dir" exts "$@")
    echo "$result"
    _trace_end count_files_with_exts "$dir" "$@"
}

count_dirs_with_prefix() {
    _trace_start
    dir="$1"; pref="$2"
    result=$(_py_count "$dir" dirs_prefix "$pref")
    echo "$result"
    _trace_end count_dirs_with_prefix "$dir" "$pref"
}

# If no Python detected, provide a find-based fallback to preserve behavior
if [ -z "$PYTHON" ]; then
    count_files_any_ext() {
        _trace_start
        dir="$1"
        if [ ! -d "$dir" ]; then
            echo 0; _trace_end count_files_any_ext "$dir"; return
        fi
        result=$(find "$dir" -maxdepth 1 -type f -name '*.*' 2>/dev/null | wc -l)
        echo "$result"
        _trace_end count_files_any_ext "$dir"
    }
    count_files_with_exts() {
        _trace_start
        dir="$1"; shift || true
        if [ ! -d "$dir" ]; then
            echo 0; _trace_end count_files_with_exts "$dir" "$@"; return
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
        _trace_end count_files_with_exts "$dir" "$@"
    }
    count_dirs_with_prefix() {
        _trace_start
        dir="$1"; prefix="$2"
        if [ ! -d "$dir" ]; then
            echo 0; _trace_end count_dirs_with_prefix "$dir" "$prefix"; return
        fi
        result=$(find "$dir" -maxdepth 1 -type d -name "${prefix}*" 2>/dev/null | wc -l)
        echo "$result"
        _trace_end count_dirs_with_prefix "$dir" "$prefix"
    }
fi

return 0
