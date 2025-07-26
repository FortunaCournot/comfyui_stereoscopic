#!/bin/sh
# Executes the whole SBS workbench pipeline again and again ...
# Copyright (c) 2025 Fortuna Cournot. MIT License.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable
COMFYUIPATH=.

cd $COMFYUIPATH

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini
if [ ! -e $CONFIGFILE ] ; then
	touch "$CONFIGFILE"
	echo "config_version=1">>"$CONFIGFILE"
	echo "COMFYUIHOST=127.0.0.1">>"$CONFIGFILE"
	echo "COMFYUIPORT=8188">>"$CONFIGFILE"
	echo "SBS_DEPTH_SCALE=1.25">>"$CONFIGFILE"
	echo "SBS_DEPTH_OFFSET=0.0">>"$CONFIGFILE"
	echo "UPSCALEMODELx4=4x_foolhardy_Remacri.pth">>"$CONFIGFILE"
	echo "UPSCALEMODELx2=4x_foolhardy_Remacri.pth">>"$CONFIGFILE"
	echo "RESCALEx4=1.0">>"$CONFIGFILE"
	echo "RESCALEx2=0.5">>"$CONFIGFILE"
fi
CONFIGFILE=`realpath "$CONFIGFILE"`
export CONFIGFILE
echo -e $"\e[1musing config file $CONFIGFILE\e[0m"
config_version=$(awk -F "=" '/config_version/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}


if test $# -ne 0
then
	# targetprefix path is relative; parent directories are created as needed
	echo "Usage: $0 "
	echo "E.g.: $0 "
else
	mkdir -p input/vr/slideshow input/vr/dubbing input/vr/scaling input/vr/fullsbs input/vr/scaling/override input/vr/singleloop input/vr/slides input/vr/starloop
	SERVERERROR=
	
	if [ -e custom_nodes/comfyui_stereoscopic/pyproject.toml ]; then
		VERSION=`cat custom_nodes/comfyui_stereoscopic/pyproject.toml | grep "version = " | grep -v "minversion" | grep -v "target-version"`
	else
		echo -e $"\e[91mError:\e[0m script not started in ComfyUI folder!"
		exit
	fi

	
	echo ""
	echo -e $"\e[97m\e[1mStereoscopic Pipeline Processing started. $VERSION\e[0m"
	echo -e $"\e[2m"
	echo "Waiting for your files to be placed in folders:"
	echo " - To create a VR video:  input/vr/dubbing" 
	echo " - To create a VR slides: input/vr/slides" 
	echo "The results will be saved to output/vr/fullsbs" 
	echo -e $"For other processings read docs on \e[36mhttps://civitai.com/models/1757677\e[0m"
	echo "" 
	
	./custom_nodes/comfyui_stereoscopic/api/status.sh
	echo " "
	
	while true;
	do
		# happens every iteration since daemon is responsibe to initially create config and detect comfyui changes
		COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
		COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
		export COMFYUIHOST COMFYUIPORT

		status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
		if [ "$status" = "closed" ]; then
			echo -ne $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT\r"
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
			STARLOOPCOUNT=`find input/vr/starloop -maxdepth 1 -type f -name '*.mp4' | wc -l`
			
			COUNT=$(( DUBCOUNT + SCALECOUNT + SBSCOUNT + OVERRIDECOUNT + SINGLELOOPCOUNT + STARLOOPCOUNT ))
			COUNTWSLIDES=$(( SLIDECOUNT + $COUNT ))
			COUNTSBSSLIDES=$(( SLIDESBSCOUNT + $COUNT ))
			if [[ $COUNT -gt 0 ]] || [[ $SLIDECOUNT -gt 1 ]] || [[ $COUNTSBSSLIDES -gt 1 ]] ; then
				echo "Found $COUNT files in incoming folders:"
				echo "$SLIDECOUNT slides, $DUBCOUNT to dub, $SBSCOUNT + $OVERRIDECOUNT for sbs, $SINGLELOOPCOUNT + $STARLOOPCOUNT to loop, $COUNTSBSSLIDES for slideshow"
				sleep 1
				./custom_nodes/comfyui_stereoscopic/api/batch_all.sh
				echo "****************************************************"
				./custom_nodes/comfyui_stereoscopic/api/status.sh				
				echo " "
			else
				BLINK=`shuf -n1 -e "..." "   "`
				echo -ne $"\e[2mWaiting for new files$BLINK\e[0m     \r"
				sleep 1
			fi
		fi
	done #KILL ME
fi
