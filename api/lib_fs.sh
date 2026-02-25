#!/bin/sh
# Filesystem helper library (baseline implementations)
# Provides simple counting helpers that currently wrap the existing
# `find ... | wc -l` behavior so callers can source this file and
# later switch to faster implementations without changing callers.

# Count all regular files (any extension) in a directory (non-recursive).
# Usage: count_files_any_ext DIR
count_files_any_ext() {
    dir="$1"
    if [ ! -d "$dir" ]; then
        echo 0
        return
    fi
    # baseline: use find (keeps behavior identical to existing scripts)
    find "$dir" -maxdepth 1 -type f -name '*.*' 2>/dev/null | wc -l
}

# Count files by a set of extensions (non-recursive).
# Usage: count_files_with_exts DIR ext1 ext2 ...
count_files_with_exts() {
    dir="$1"
    shift || true
    if [ ! -d "$dir" ]; then
        echo 0
        return
    fi
    total=0
    for ext in "$@"; do
        # normalize extension (allow both 'mp4' and '.mp4')
        e="$ext"
        case "$e" in
            .* ) e="${e#*.}" ;;
        esac
        cnt=$(find "$dir" -maxdepth 1 -type f -iname "*.$e" 2>/dev/null | wc -l)
        total=$((total + cnt))
    done
    echo "$total"
}

# Count directories by name prefix (non-recursive).
# Usage: count_dirs_with_prefix DIR PREFIX
count_dirs_with_prefix() {
    dir="$1"
    prefix="$2"
    if [ ! -d "$dir" ]; then
        echo 0
        return
    fi
    find "$dir" -maxdepth 1 -type d -name "${prefix}*" 2>/dev/null | wc -l
}

return 0
