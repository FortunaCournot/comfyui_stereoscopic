#!/bin/sh
# Executes the whole SBS workbench pipeline again and again ...
# Copyright (c) 2025 Fortuna Cournot. MIT License.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable
COMFYUIPATH=`realpath $(dirname "$0")/../../..`

cd $COMFYUIPATH

echo "trying to remove intermediate files..."
rm -rf output/vr/*/intermediate/* 2>/dev/null

FREESPACE=$(df -khBG . | tail -n1 | awk '{print $4}')
FREESPACE=${FREESPACE%G}

echo "$FREESPACE""G left on device."
