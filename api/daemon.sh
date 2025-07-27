#!/bin/sh
# Executes the whole SBS workbench pipeline again and again ...
# Copyright (c) 2025 Fortuna Cournot. MIT License.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable
COMFYUIPATH=`realpath $(dirname "$0")/../../..`

cd $COMFYUIPATH

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini
if [ ! -e $CONFIGFILE ] ; then
	E:\SD\Software\ComfyUI_windows_portable_nvidia\ComfyUI_windows_portable\ComfyUI\models\upscale_models

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
	echo "FFMPEGPATHPREFIX=">>"$CONFIGFILE"
	echo "FLORENCE2MODEL=microsoft/Florence-2-base">>"$CONFIGFILE"

	if ! command -v ffmpeg >/dev/null 2>&1
	then
		echo -e $"\e[91mError:\e[0m ffmpeg could not be found in systempath."
		exit 1
	fi
fi

CONFIGFILE=`realpath "$CONFIGFILE"`
export CONFIGFILE
echo -e $"\e[1musing config file $CONFIGFILE\e[0m"
config_version=$(awk -F "=" '/config_version/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}
UPSCALEMODELx4=$(awk -F "=" '/UPSCALEMODELx4/ {print $2}' $CONFIGFILE) ; UPSCALEMODELx4=${UPSCALEMODELx4:-"4x_foolhardy_Remacri.pth"}
UPSCALEMODELx2=$(awk -F "=" '/UPSCALEMODELx2/ {print $2}' $CONFIGFILE) ; UPSCALEMODELx2=${UPSCALEMODELx2:-"4x_foolhardy_Remacri.pth"}
FLORENCE2MODEL=$(awk -F "=" '/FLORENCE2MODEL/ {print $2}' $CONFIGFILE) ; FLORENCE2MODEL=${FLORENCE2MODEL:-"microsoft/Florence-2-base"}

CONFIGERROR=
if ! command -v "$(FFMPEGPATHPREFIX)ffmpeg" >/dev/null 2>&1
then
	echo -e $"\e[91mError:\e[0m ffmpeg could not be found."
	CONFIGERROR="x"
fi
if [ ! -e models/upscale_models/$UPSCALEMODELx4 ]; then
	echo -e $"\e[91mError:\e[0m Upscale model $UPSCALEMODELx4 could not be found in models/upscale_models. Use Model Manager to install."
	CONFIGERROR="x"
fi
if [ ! -e models/upscale_models/$UPSCALEMODELx2 ]; then
	echo -e $"\e[91mError:\e[0m Upscale model $UPSCALEMODELx2 could not be found in models/upscale_models. Use Model Manager to install."
	CONFIGERROR="x"
fi
if [ ! -d custom_nodes/ComfyUI-Manager ] && [ ! -d custom_nodes/ComfyUI-Manager-main ]; then
	echo -e $"\e[91mError:\e[0m ComfyUI-Manager could not be found. Install from \e[36mhttps://github.com/Comfy-Org/ComfyUI-Manager\e[0m"
	CONFIGERROR="x"
fi
if [ ! -d custom_nodes/comfyui_controlnet_aux ]; then
	echo -e $"\e[91mError:\e[0m Custom nodes comfyui_controlnet_aux could not be found. Use Custom Nodes Manager to install v1.1.0."
	CONFIGERROR="x"
fi
if [ ! -d custom_nodes/comfyui-videohelpersuite ]; then
	echo -e $"\e[91mError:\e[0m Custom nodes comfyui-videohelpersuite could not be found. Use Custom Nodes Manager to install."
	CONFIGERROR="x"
fi
if [ ! -d custom_nodes/bjornulf_custom_nodes ]; then
	echo -e $"\e[91mError:\e[0m Custom nodes bjornulf_custom_nodes could not be found. Use Custom Nodes Manager to install."
	CONFIGERROR="x"
fi
if [ ! -d custom_nodes/comfyui-easy-use ]; then
	echo -e $"\e[91mError:\e[0m Custom nodes comfyui-easy-use could not be found. Use Custom Nodes Manager to install."
	CONFIGERROR="x"
fi
if [ ! -d custom_nodes/comfyui-custom-scripts ]; then
	echo -e $"\e[91mError:\e[0m Custom nodes comfyui-custom-scripts could not be found. Use Custom Nodes Manager to install."
	CONFIGERROR="x"
fi
if [ ! -d custom_nodes/ComfyLiterals ]; then
	echo -e $"\e[91mError:\e[0m Custom nodes ComfyLiterals could not be found. Use Custom Nodes Manager to install."
	CONFIGERROR="x"
fi
if [ ! -d custom_nodes/comfy-mtb ]; then
	echo -e $"\e[91mError:\e[0m Custom nodes comfy-mtb could not be found. Use Custom Nodes Manager to install."
	CONFIGERROR="x"
fi
if [[ ! -z $CONFIGERROR ]]; then
	exit
fi


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
