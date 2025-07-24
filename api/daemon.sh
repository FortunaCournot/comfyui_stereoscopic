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
	mkdir -p input/vr/slideshow input/vr/dubbing input/vr/scaling input/vr/fullsbs input/vr/scaling/override input/vr/singleloop input/vr/slides input/vr/starloop
	SERVERERROR=
	
	echo "Stereoscopic Pipeline Processing started."
	echo ""
	echo "Waiting for your files to be placed in folders:"
	echo " - To create a VR video:  input/vr/dubbing" 
	echo " - To create a VR slides: input/vr/slides" 
	echo "The results will be saved to output/vr/fullsbs" 
	echo "" 
	
	while true;
	do
		status=`true &>/dev/null </dev/tcp/127.0.0.1/8188 && echo open || echo closed`
		if [ "$status" = "closed" ]; then
			echo -ne "Error: ComfyUI not present. Ensure it is running on port 8188\r"
			SERVERERROR="x"
		else
			if [[ ! -z $SERVERERROR ]]; then
				echo ""
				SERVERERROR=
			fi
			
			SLIDECOUNT=`find input/vr/slides -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
			SLIDESBSCOUNT=`find input/vr/slideshow -maxdepth 1 -type f -name '*.png' | wc -l`
			DUBCOUNT=`find input/vr/dubbing -maxdepth 1 -type f -name '*.mp4' | wc -l`
			SCALECOUNT=`find input/vr/scaling -maxdepth 1 -type f -name '*.mp4' | wc -l`
			SBSCOUNT=`find input/vr/fullsbs -maxdepth 1 -type f -name '*.mp4' -o -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
			OVERRIDECOUNT=`find input/vr/scaling/override -maxdepth 1 -type f -name '*.mp4' | wc -l`
			SINGLELOOPCOUNT=`find input/vr/singleloop -maxdepth 1 -type f -name '*.mp4' | wc -l`
			
			COUNT=$(( DUBCOUNT + SCALECOUNT + SBSCOUNT + OVERRIDECOUNT + SINGLELOOPCOUNT ))
			COUNTWSLIDES=$(( SLIDECOUNT + $COUNT ))
			COUNTSBSSLIDES=$(( SLIDESBSCOUNT + $COUNT ))
			if [[ $COUNT -gt 0 ]] || [[ $SLIDECOUNT -gt 1 ]] || [[ $COUNTSBSSLIDES -gt 1 ]] ; then
				echo "Found $COUNT files in incoming folders. ($SLIDECOUNT slides, $DUBCOUNT to dub, $SBSCOUNT + $OVERRIDECOUNT for sbs, $SINGLELOOPCOUNT to loop, $COUNTSBSSLIDES for slideshow)"
				sleep 1
				./custom_nodes/comfyui_stereoscopic/api/batch_all.sh
				echo "****************************************************"
			else
				BLINK=`shuf -n1 -e "..." "   "`
				echo -ne "Waiting for new files$BLINK     \r"
				sleep 1
			fi
		fi
	done #KILL ME
fi
