"""
comfyui_logwatch.py
Copyright (c) 2026 Fortuna Cournot. MIT License.

Purpose
-------
This helper does not start ComfyUI directly from a batch file. Instead, it
acts as a supervising wrapper around the ComfyUI process. It reads the live
console output, keeps that output visible in the terminal, and writes the same
output to a log file at the same time.

The main motivation is a specific failure mode: ComfyUI can crash internally in
one of its worker threads while the external Python client does not receive a
useful error signal. In that case, the batch logic cannot reliably detect that
ComfyUI is already in a broken state. The only useful evidence may appear in
ComfyUI's own console output.

This script solves that problem without replacing the already existing restart
behavior of the Windows batch files. The batch files still restart themselves
through `%0`. The only difference is that ComfyUI is now started through this
helper. As soon as a known fatal log line is detected, this script terminates
the complete ComfyUI process tree. The existing `%0` loop then starts ComfyUI
again.

How it works
------------
1. The script starts the provided ComfyUI command as a child process.
2. `stdout` and `stderr` are merged.
3. Every emitted line is immediately:
   - written back to the current console, and
   - appended to a log file.
4. Every line is checked against a small set of known fatal patterns.
5. If such a pattern is found, an optional marker file is updated and the
   complete process tree is terminated through `taskkill /T /F`.

Important property
------------------
ComfyUI output stays visible. This script does not replace logging. It extends
the normal console behavior with mirroring and crash pattern detection.

Why kill the process tree instead of relying on ComfyUI exit codes?
-------------------------------------------------------------------
For the relevant failure mode, the core issue is that ComfyUI may not stop in a
way that provides a useful return code to the surrounding automation. Because
of that, this helper reacts to known fatal log patterns instead of waiting for
a clean error exit path.

Detected patterns
-----------------
The current pattern list is intentionally small and conservative. It focuses on
clearly fatal states such as:
- `Exception in thread ... prompt_worker`
- `torch.AcceleratorError`
- `CUDA error: unknown error`
- `cudaErrorUnknown`
- `device-side assertions`

The goal is to catch critical failures, not every warning or arbitrary
stacktrace.

Limits
------
- The script only detects failures that appear in ComfyUI console output.
- If ComfyUI hangs without producing further output, this helper cannot detect
  that state automatically.
- Detection is pattern-based. New crash forms must be added to
  `CRASH_PATTERNS` when needed.
- The implementation is Windows-specific because process tree termination uses
  `taskkill`.

Invocation
----------
The script expects its own parameters first and the target command afterwards.
The separator is `--`.

Example:
    python comfyui_logwatch.py \
        --log-file ComfyUI\\user\\default\\comfyui_stereoscopic\\comfyui-server.log \
        --marker-file ComfyUI\\user\\default\\comfyui_stereoscopic\\.comfyui_logwatch_crash \
        -- \
        .\\python_embeded\\python.exe -u -s ComfyUI\\main.py --windows-standalone-build

Parameters
----------
--log-file:
    Target path for the continuously appended server log.

--marker-file:
    Optional path for a marker file. When a fatal pattern is detected, the
    triggering line is appended there together with a timestamp.

command:
    The actual ComfyUI start command including all arguments.

Project usage
-------------
This script is meant to be used by the three existing start BAT files outside
the repository:
- `run_nvidia_gpu.bat`
- `run_cpu.bat`
- `run_nvidia_gpu_fast_fp16_accumulation.bat`

Those files keep their `%0` restart loop. `comfyui_logwatch.py` only provides
monitoring and additional logging.
"""

import argparse
import codecs
import os
import queue
import re
import subprocess
import sys
import threading
import time


CRASH_PATTERNS = [
    re.compile(r"Exception in thread .*prompt_worker", re.IGNORECASE),
    re.compile(r"torch\.AcceleratorError", re.IGNORECASE),
    re.compile(r"CUDA error: unknown error", re.IGNORECASE),
    re.compile(r"cudaErrorUnknown", re.IGNORECASE),
    re.compile(r"device-side assertions", re.IGNORECASE),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run ComfyUI, mirror output to console and log file, and stop on known fatal log patterns."
    )
    parser.add_argument("--log-file", required=True)
    parser.add_argument("--marker-file", required=False, default="")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.command and args.command[0] == "--":
        args.command = args.command[1:]
    if not args.command:
        parser.error("missing command after '--'")
    return args


def ensure_parent_dir(path: str) -> None:
    parent = os.path.dirname(os.path.abspath(path))
    if parent:
        os.makedirs(parent, exist_ok=True)


def write_marker(marker_file: str, line: str) -> None:
    if not marker_file:
        return
    ensure_parent_dir(marker_file)
    with open(marker_file, "a", encoding="utf-8") as handle:
        handle.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {line}")
        if not line.endswith("\n"):
            handle.write("\n")


def stream_reader(stream, out_queue: queue.Queue) -> None:
    try:
        while True:
            chunk = os.read(stream.fileno(), 4096)
            if not chunk:
                break
            out_queue.put(chunk)
    finally:
        try:
            stream.close()
        except Exception:
            pass
        out_queue.put(None)


def kill_process_tree(pid: int) -> None:
    subprocess.run(
        ["taskkill", "/PID", str(pid), "/T", "/F"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )


def matches_crash(line: str) -> bool:
    return any(pattern.search(line) for pattern in CRASH_PATTERNS)


def build_child_env() -> dict[str, str]:
    env = os.environ.copy()
    try:
        terminal_size = os.get_terminal_size(sys.stdout.fileno())
    except OSError:
        try:
            terminal_size = os.get_terminal_size()
        except OSError:
            terminal_size = None

    if terminal_size is not None:
        columns = str(terminal_size.columns)
        lines = str(terminal_size.lines)
        env.setdefault("COLUMNS", columns)
        env.setdefault("LINES", lines)
        env.setdefault("TQDM_NCOLS", columns)

    return env


def main() -> int:
    args = parse_args()
    # If marker file not explicitly provided, allow an environment variable
    # to define the canonical marker path used by other scripts.
    if not args.marker_file:
        args.marker_file = os.environ.get("COMFYUI_LOGWATCH_MARKER", "user/default/comfyui_stereoscopic/.comfyui_logwatch_crash")

    ensure_parent_dir(args.log_file)

    # Decode the child output explicitly as UTF-8. Read in chunks rather than
    # lines so carriage-return based progress displays are forwarded without
    # waiting for a trailing newline.
    with open(args.log_file, "a", encoding="utf-8", buffering=1) as log_handle:
        log_handle.write(f"\n===== ComfyUI start {time.strftime('%Y-%m-%d %H:%M:%S')} =====\n")
        child_env = build_child_env()
        process = subprocess.Popen(
            args.command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=0,
            cwd=os.getcwd(),
            env=child_env,
        )

        out_queue: queue.Queue = queue.Queue()
        reader = threading.Thread(target=stream_reader, args=(process.stdout, out_queue), daemon=True)
        reader.start()

        stream_done = False
        detected_line = ""
        decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")
        pending_line = ""

        def check_pending_lines(flush_final: bool = False) -> None:
            nonlocal pending_line, detected_line
            while "\n" in pending_line:
                line, pending_line = pending_line.split("\n", 1)
                line = f"{line}\n"
                if not detected_line and matches_crash(line):
                    detected_line = line
                    notice = "[comfyui_logwatch] fatal pattern detected, terminating ComfyUI process tree\n"
                    log_handle.write(notice)
                    log_handle.flush()
                    write_marker(args.marker_file, line)
                    kill_process_tree(process.pid)
            if flush_final and pending_line and not detected_line and matches_crash(pending_line):
                detected_line = pending_line
                notice = "[comfyui_logwatch] fatal pattern detected, terminating ComfyUI process tree\n"
                log_handle.write(notice)
                log_handle.flush()
                write_marker(args.marker_file, pending_line)
                kill_process_tree(process.pid)

        while True:
            try:
                item = out_queue.get(timeout=0.2)
            except queue.Empty:
                if stream_done and process.poll() is not None:
                    break
                continue

            if item is None:
                stream_done = True
                remaining_text = decoder.decode(b"", final=True)
                if remaining_text:
                    sys.stdout.write(remaining_text)
                    sys.stdout.flush()
                    log_handle.write(remaining_text)
                    pending_line += remaining_text
                check_pending_lines(flush_final=True)
                if process.poll() is not None:
                    break
                continue

            text_chunk = decoder.decode(item)
            sys.stdout.write(text_chunk)
            sys.stdout.flush()
            log_handle.write(text_chunk)
            pending_line += text_chunk
            check_pending_lines()

        return process.wait()


if __name__ == "__main__":
    raise SystemExit(main())