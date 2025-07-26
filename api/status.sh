#!/bin/sh
# Executes the whole SBS workbench pipeline again and again ...
# Copyright (c) 2025 Fortuna Cournot. MIT License.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable
COMFYUIPATH=.

cd $COMFYUIPATH

echo "+++ Summary of completed files per folder +++"
du --inodes -d 0 -S output/vr/*       | { while read inodes path; do files=`ls -F $path |grep -v / | wc -l`; printf "%s\t%s\n" "$files" "$path"; done }
du --inodes -d 0 -S output/vr/*/final | { while read inodes path; do files=`ls -F $path |grep -v / | wc -l`; printf "%s\t%s\n" "$files" "$path"; done }
