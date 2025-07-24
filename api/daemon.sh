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
	mkdir -p input/slideshow_in input/dubbing_in input/upscale_in input/sbs_in input/upscale_in/override input/singleloop_in
	while true;
	do
		SLIDECOUNT=`find input/slides_in -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
		DUBCOUNT=`find input/dubbing_in -maxdepth 1 -type f -name '*.mp4' | wc -l`
		SCALECOUNT=`find input/upscale_in -maxdepth 1 -type f -name '*.mp4' | wc -l`
		SBSCOUNT=`find input/sbs_in -maxdepth 1 -type f -name '*.mp4' -o -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
		OVERRIDECOUNT=`find input/upscale_in/override -maxdepth 1 -type f -name '*.mp4' | wc -l`
		SINGLELOOPCOUNT=`find input/singleloop_in -maxdepth 1 -type f -name '*.mp4' | wc -l`
		
		COUNT=$(( DUBCOUNT + SCALECOUNT + SBSCOUNT + OVERRIDECOUNT + SINGLELOOPCOUNT ))
		COUNTWSLIDES=$(( SLIDECOUNT + $COUNT ))
		if [[ $COUNT -gt 0 ]] || [[ $SLIDECOUNT -gt 1 ]] ; then
			echo "Found $COUNT files in incoming folders. ($SLIDECOUNT slides, $DUBCOUNT to dub, $SBSCOUNT + $OVERRIDECOUNT for sbs, $SINGLELOOPCOUNT to loop)"
		
			./custom_nodes/comfyui_stereoscopic/api/batch_all.sh
			echo "****************************************************"
		else
			BLINK=`shuf -n1 -e "..." "   "`
			echo -ne "Waiting for new files$BLINK     \r"
			sleep 1
		fi
	done #KILL ME
fi
