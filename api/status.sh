#!/bin/sh
# Executes the whole SBS workbench pipeline again and again ...
# Copyright (c) 2025 Fortuna Cournot. MIT License.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable

if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`

cd $COMFYUIPATH

# filesystem helpers (canonical sourcing)
if [ -z "$COMFYUIPATH" ]; then
	echo "Error: COMFYUIPATH not set in $(basename \"$0\") (cwd=$(pwd)). Start script from repository root."; exit 1;
fi
LIB_FS="$COMFYUIPATH/custom_nodes/comfyui_stereoscopic/api/lib_fs.sh"
if [ -f "$LIB_FS" ]; then
	. "$LIB_FS" || { echo "Error: failed to source canonical $LIB_FS in $(basename \"$0\") (cwd=$(pwd))"; exit 1; }
else
	echo "Error: required lib_fs not found at canonical path: $LIB_FS"; exit 1;
fi
if ! command -v count_files_any_ext >/dev/null 2>&1 || ! command -v count_files_with_exts >/dev/null 2>&1 ; then
	echo "Error: lib_fs functions missing after sourcing $LIB_FS in $(basename \"$0\") (cwd=$(pwd))"; exit 1;
fi

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

export CONFIGFILE
if [ -e $CONFIGFILE ] ; then
	loglevel=$(awk -F "=" '/loglevel=/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
	[ $loglevel -ge 2 ] && set -x
    config_version=$(awk -F "=" '/config_version=/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
	COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST=/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
	COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT=/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
	export COMFYUIHOST COMFYUIPORT
else
    touch "$CONFIGFILE"
    echo "config_version=1">>"$CONFIGFILE"
fi

"$PYTHON" - <<'PY'
import os
from pathlib import Path

ROOT = Path('.')
IGNORED_BASENAMES = {"thumbs.db", "desktop.ini", ".ds_store"}


def iter_files(directory: Path):
	try:
		with os.scandir(directory) as entries:
			for entry in entries:
				try:
					if entry.is_file(follow_symlinks=False):
						yield entry
				except OSError:
					continue
	except OSError:
		return


def count_visible_files(directory: Path, exclude_txt: bool = False) -> int:
	count = 0
	for entry in iter_files(directory):
		name = entry.name
		lower_name = name.lower()
		if '.' not in name or lower_name in IGNORED_BASENAMES:
			continue
		if exclude_txt and lower_name.endswith('.txt'):
			continue
		count += 1
	return count


def dir_size_bytes(directory: Path) -> int:
	total = 0
	if not directory.exists():
		return total
	for root, _, files in os.walk(directory):
		for filename in files:
			file_path = Path(root) / filename
			try:
				total += file_path.stat().st_size
			except OSError:
				continue
	return total


def format_gib_rounded(byte_count: int) -> str:
	gib = (byte_count + (1024 ** 3) - 1) // (1024 ** 3)
	return f"{gib}G"


def display_path(path: Path) -> str:
	return path.as_posix().lstrip('./')


def colorize(text: str, *codes: str) -> str:
	prefix = ''.join(f"\033[{code}m" for code in codes)
	return f"{prefix}{text}\033[0m"


print(colorize("+++ Summary of Disk Usage +++", "4"))
for rel in (Path('input/vr'), Path('output/vr')):
	print(f"{format_gib_rounded(dir_size_bytes(rel))}\t{display_path(rel)}")
print(" ")

completed_paths = []
for base in (Path('output/vr'), Path('output/vr/dubbing'), Path('output/vr/tasks')):
	if not base.is_dir():
		continue
	try:
		children = sorted((child for child in base.iterdir() if child.is_dir()), key=lambda p: p.as_posix())
	except OSError:
		continue
	for child in children:
		files = count_visible_files(child, exclude_txt=True)
		if files > 0:
			completed_paths.append((files, display_path(child)))

if completed_paths:
	print(colorize("+++ Summary of Completed Files per Folder +++", "4", "32"))
	for files, path in completed_paths:
		print(colorize(f"{files}\t{path}", "92"))

error_entries = []
stopped_entries = []
input_root = Path('input/vr')
if input_root.is_dir():
	for root, dirs, _ in os.walk(input_root):
		for dirname in sorted(dirs):
			if dirname not in ('error', 'stopped'):
				continue
			path = Path(root) / dirname
			files = count_visible_files(path, exclude_txt=False)
			if files <= 0:
				continue
			entry = (files, display_path(path))
			if dirname == 'error':
				error_entries.append(entry)
			else:
				stopped_entries.append(entry)

if error_entries or stopped_entries:
	print(" ")
	print(colorize("+++ Summary of Folders with Errors +++", "31", "4"))
	if error_entries:
		for files, path in error_entries:
			print(colorize(f"{files}\t{path}", "91"))
	if stopped_entries:
		for files, path in stopped_entries:
			print(colorize(f"{files}\t{path}", "93"))
PY
exit 0
