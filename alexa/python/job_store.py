"""Thread-safe in-memory storage for open job count."""

from __future__ import annotations

import threading

_lock = threading.RLock()
_open_jobs = 0


def get_open_jobs() -> int:
    """Return current open job count."""
    with _lock:
        return int(_open_jobs)


def set_open_jobs(value: int):
    """Set open job count (clamped to >= 0)."""
    global _open_jobs
    with _lock:
        _open_jobs = max(0, int(value))


def increment_jobs(n: int = 1):
    """Increase open job count by n."""
    global _open_jobs
    with _lock:
        _open_jobs = max(0, int(_open_jobs) + int(n))


def decrement_jobs(n: int = 1):
    """Decrease open job count by n (never below zero)."""
    global _open_jobs
    with _lock:
        _open_jobs = max(0, int(_open_jobs) - int(n))
