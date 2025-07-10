#!/bin/sh
# Creates SBS video from base video in outsput/sbsin folder (input)
# Copyright (c) 2025 Oliver Rode. MIT License.

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).
# Prerequisite: Placed sbs_api.py somewhere and configured path variables below.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable
COMFYUIPATH=.

if test $# -ne 0
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 "
    echo "E.g.: $0 "
else
	for nextscript in $COMFYUIPATH/output/sbs/*.tmpsbs/concat.sh $COMFYUIPATH/output/upscale/*.tmpupscale/concat.sh; do
		/bin/bash "$nextscript"
	done
	echo "done."
fi

