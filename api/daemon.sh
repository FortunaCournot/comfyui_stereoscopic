#!/bin/sh
# Executes the whole SBS workbench pipeline again and again ...
# Copyright (c) 2025 Fortuna Cournot. MIT License.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable
COMFYUIPATH=.

cd $COMFYUIPATH

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

export CONFIGFILE

if test $# -ne 0
then
	# targetprefix path is relative; parent directories are created as needed
	echo "Usage: $0 "
	echo "E.g.: $0 "
else
	mkdir -p input/vr/slideshow input/vr/dubbing input/vr/scaling input/vr/fullsbs input/vr/scaling/override input/vr/singleloop input/vr/slides input/vr/starloop
	SERVERERROR=
	
	echo "Stereoscopic Pipeline Processing started. $VERSION"
	echo ""
	echo "Waiting for your files to be placed in folders:"
	echo " - To create a VR video:  input/vr/dubbing" 
	echo " - To create a VR slides: input/vr/slides" 
	echo "The results will be saved to output/vr/fullsbs" 
	echo "For other processings read docs on https://civitai.com/models/1757677" 
	echo "" 
	
	./custom_nodes/comfyui_stereoscopic/api/status.sh
	echo " "
	
	while true;
	do
		if [ -e $CONFIGFILE ] ; then
			# happens every iteration since daemon is responsibe to initially create config and detect comfyui changes
			config_version=$(awk -F "=" '/config_version/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
			COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
			COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
			export COMFYUIHOST COMFYUIPORT
		else
			touch "$CONFIGFILE"
			echo "config_version=1">>"$CONFIGFILE"
			echo "COMFYUIHOST=127.0.0.1">>"$CONFIGFILE"
			echo "COMFYUIPORT=8188">>"$CONFIGFILE"
		fi

		if [ -e custom_nodes/comfyui_stereoscopic/pyproject.toml ]; then
			VERSION=`cat custom_nodes/comfyui_stereoscopic/pyproject.toml | grep "version = " | grep -v "minversion" | grep -v "target-version"`
		else
			echo "Error: script not started in ComfyUI folder!"
			exit
		fi
	
		status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
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
				./custom_nodes/comfyui_stereoscopic/api/status.sh				
				echo " "
				BLINK=`shuf -n1 -e "..." "   "`
				echo -ne "Waiting for new files$BLINK     \r"
				sleep 1
			fi
		fi
	done #KILL ME
fi
