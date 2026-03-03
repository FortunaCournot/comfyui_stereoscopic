#!/usr/bin/env python3
"""
Compute file counts for directories under input/vr and output/vr and
write them as a simple property file. Keys are of the form:

<type>|<path>=<count>

where <type> is one of: any, images, videos
Path is relative path (unix style) like "output/vr/scaling".

This script is intentionally conservative and only counts immediate files
in each directory (no recursion), matching the existing lib_fs helper semantics.
"""

import os
import sys
from pathlib import Path

ROOT = Path('.')
OUT_FILE = os.environ.get('FS_STATUS_FILE', 'user/default/comfyui_stereoscopic/.fs_status.properties')
UNUSED_PROPS = Path('user/default/comfyui_stereoscopic/unused.properties')

IMAGE_EXTS = ('.png', '.jpg', '.jpeg', '.webp', '.PNG', '.JPG', '.JPEG', '.WEBP')
VIDEO_EXTS = ('.mp4', '.webm', '.ts', '.mkv', '.avi', '.mov', '.MP4', '.WEBM', '.TS', '.MKV', '.AVI', '.MOV')
AUDIO_EXTS = ('.flac', '.mp3', '.wav', '.aac', '.m4a', '.FLAC', '.MP3', '.WAV', '.AAC', '.M4A')

paths_to_scan = []

# collect top-level children of input/vr and output/vr, and one-level nested subdirs (e.g. dubbing/sfx)
for base in ('input/vr', 'output/vr'):
    p = ROOT / base
    if not p.is_dir():
        continue
    for child in sorted(p.iterdir()):
        if child.is_dir():
            paths_to_scan.append(str(child.as_posix()))
            # include immediate subdirs (useful for multi-level stages like dubbing/sfx)
            for sub in sorted(child.iterdir()):
                if sub.is_dir():
                    # skip descending into tasks here; tasks handled specially below
                    if child.name == 'tasks':
                        # include only tasks/<task>
                        paths_to_scan.append(str(sub.as_posix()))
                        # also include tasks/<task>/wait as separate counter (if present)
                        try:
                            wait_dir = sub / 'wait'
                            if wait_dir.is_dir():
                                paths_to_scan.append(str(wait_dir.as_posix()))
                        except Exception:
                            pass
                    else:
                        paths_to_scan.append(str((child / sub.name).as_posix()))

# remove duplicates while preserving order
seen = set()
unique_paths = []
for p in paths_to_scan:
    if p not in seen:
        unique_paths.append(p)
        seen.add(p)

entries = []
disabled = {
    'stage': set(),
    'task': set(),
    'customtask': set()
}
# parse unused.properties if present; values kept as-is (comma-separated)
if UNUSED_PROPS.exists():
    try:
        with UNUSED_PROPS.open('r', encoding='utf-8') as fh:
            for line in fh:
                line=line.strip()
                if not line or line.startswith('#'):
                    continue
                if '=' not in line:
                    continue
                k,v = line.split('=',1)
                k=k.strip()
                v=v.strip().replace('\r','')
                if k in disabled:
                    for item in v.split(','):
                        item=item.strip()
                        if item:
                            disabled[k].add(item)
    except Exception:
        pass


def is_disabled_name(name):
    # name may be like 'slides' or 'dubbing/sfx' or 'tasks/foo' or 'tasks/_bar'
    if name.startswith('tasks/_'):
        key='customtask'
    elif name.startswith('tasks/'):
        key='task'
    else:
        key='stage'
    return name in disabled.get(key, set())

for p in unique_paths:
    # decide the logical name for disabled checks
    rel = p
    # make relative like 'slides' or 'dubbing/sfx' or 'tasks/<task>'
    if rel.startswith('input/vr/'):
        rel_name = rel[len('input/vr/'):]
    elif rel.startswith('output/vr/'):
        rel_name = rel[len('output/vr/'):]
    else:
        rel_name = os.path.relpath(rel)

    # Normalize rel_name to not end with '/'
    rel_name = rel_name.rstrip('/')

    # If disabled, report zeros
    if is_disabled_name(rel_name):
        any_cnt = 0
        img_cnt = 0
        vid_cnt = 0
        aud_cnt = 0
    else:
        try:
            it = list(os.scandir(p))
        except Exception:
            any_cnt = 0
            img_cnt = 0
            vid_cnt = 0
            aud_cnt = 0
        else:
            # Only count files that have a suffix (dot in basename) for all counters.
            # This prevents counting temporary/marker files without extensions.
            file_names = [e.name for e in it if e.is_file() and '.' in e.name]
            any_cnt = len(file_names)
            lower_names = [n.lower() for n in file_names]
            img_cnt = sum(1 for n in lower_names if n.endswith(IMAGE_EXTS))
            vid_cnt = sum(1 for n in lower_names if n.endswith(VIDEO_EXTS))
            aud_cnt = sum(1 for n in lower_names if n.endswith(AUDIO_EXTS))

    entries.append(f"any|{p}={any_cnt}")
    entries.append(f"images|{p}={img_cnt}")
    entries.append(f"videos|{p}={vid_cnt}")
    entries.append(f"audio|{p}={aud_cnt}")

# write temporary file atomically
out_path = Path(OUT_FILE)
out_path.parent.mkdir(parents=True, exist_ok=True)
tmp = out_path.with_suffix('.tmp')
with tmp.open('w', encoding='utf-8') as fh:
    for line in entries:
        fh.write(line + '\n')
# move into place
try:
    tmp.replace(out_path)
except Exception:
    # fallback to write directly
    with out_path.open('w', encoding='utf-8') as fh:
        for line in entries:
            fh.write(line + '\n')

sys.exit(0)
