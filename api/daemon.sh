#!/bin/sh
# Executes the whole SBS workbench pipeline again and again ...
# Copyright (c) 2025 Fortuna Cournot. MIT License.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable
COMFYUIPATH=.

cd $COMFYUIPATH

if test $# -ne 0
then
	# targetprefix path is relative; parent directories are created as needed
	echo "Usage: $0 "
	echo "E.g.: $0 "
else
	while true;
	do
		SLIDECOUNT=`find input/slideshow_in -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
		DUBCOUNT=`find input/dubbing_in -maxdepth 1 -type f -name '*.mp4' | wc -l`
		SCALECOUNT=`find input/upscale_in -maxdepth 1 -type f -name '*.mp4' | wc -l`
		SBSCOUNT=`find input/sbs_in -maxdepth 1 -type f -name '*.mp4' -o -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
		OVERRIDECOUNT=`find input/upscale_in/override -maxdepth 1 -type f -name '*.mp4' | wc -l`
		
		COUNT=$(( SLIDECOUNT + DUBCOUNT + SCALECOUNT + SBSCOUNT + OVERRIDECOUNT ))
		if [[ $COUNT -gt 0 ]] ; then
			echo "Found $COUNT files in incoming folders."
		
			./custom_nodes/comfyui_stereoscopic/api/batch_all.sh
			echo "****************************************************"
		else
			echo -ne "Waiting for new files...  \r"
			sleep 2s
		fi
	done #KILL ME
fi
