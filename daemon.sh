#!/bin/sh
# Executes the whole SBS workbench pipeline again and again ...
# Copyright (c) 2025 Fortuna Cournot. MIT License.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable
COMFYUIPATH=`realpath $(dirname "$0")/../..`

cd $COMFYUIPATH

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini
if [ ! -e $CONFIGFILE ] ; then

	touch "$CONFIGFILE"
	echo "# --- comfyui_stereoscopic config  ---">>"$CONFIGFILE"
	echo "config_version=1">>"$CONFIGFILE"
	echo "# --- comfyui server config ---">>"$CONFIGFILE"
	echo "COMFYUIHOST=127.0.0.1">>"$CONFIGFILE"
	echo "COMFYUIPORT=8188">>"$CONFIGFILE"
	echo "# --- video config ---">>"$CONFIGFILE"
	echo "FFMPEGPATHPREFIX=">>"$CONFIGFILE"
	echo "MAXFPS=30">>"$CONFIGFILE"
	echo "VIDEO_FORMAT=video/h264-mp4">>"$CONFIGFILE"
	echo "VIDEO_PIXFMT=yuv420p">>"$CONFIGFILE"
	echo "VIDEO_CRF=17">>"$CONFIGFILE"
	echo "# --- scaling config ---">>"$CONFIGFILE"
	echo "UPSCALEMODELx4=RealESRGAN_x4plus.pth">>"$CONFIGFILE"
	echo "RESCALEx4=1.0">>"$CONFIGFILE"
	echo "UPSCALEMODELx2=RealESRGAN_x4plus.pth">>"$CONFIGFILE"
	echo "RESCALEx2=0.5">>"$CONFIGFILE"
	echo "SCALEBLENDFACTOR=0.7">>"$CONFIGFILE"
	echo "SCALESIGMARESOLUTION=1920.0">>"$CONFIGFILE"
	echo "# --- sbs converter config ---">>"$CONFIGFILE"
	echo "SBS_DEPTH_SCALE=1.25">>"$CONFIGFILE"
	echo "SBS_DEPTH_OFFSET=0.0">>"$CONFIGFILE"
	echo "DEPTH_MODEL_CKPT=depth_anything_v2_vitl.pth">>"$CONFIGFILE"
	echo "# --- dubbing config ---">>"$CONFIGFILE"
	echo "FLORENCE2MODEL=microsoft/Florence-2-base">>"$CONFIGFILE"
	# TODO:
	echo "SPLITSEGMENTTIME=1">>"$CONFIGFILE"


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
UPSCALEMODELx4=$(awk -F "=" '/UPSCALEMODELx4/ {print $2}' $CONFIGFILE) ; UPSCALEMODELx4=${UPSCALEMODELx4:-"RealESRGAN_x4plus.pth"}
UPSCALEMODELx2=$(awk -F "=" '/UPSCALEMODELx2/ {print $2}' $CONFIGFILE) ; UPSCALEMODELx2=${UPSCALEMODELx2:-"RealESRGAN_x4plus.pth"}
FLORENCE2MODEL=$(awk -F "=" '/FLORENCE2MODEL/ {print $2}' $CONFIGFILE) ; FLORENCE2MODEL=${FLORENCE2MODEL:-"microsoft/Florence-2-base"}
DEPTH_MODEL_CKPT=$(awk -F "=" '/DEPTH_MODEL_CKPT/ {print $2}' $CONFIGFILE) ; DEPTH_MODEL_CKPT=${DEPTH_MODEL_CKPT:-"depth_anything_v2_vitl.pth"}

CONFIGERROR=

### CHECK TOOLS ###
if ! command -v $FFMPEGPATHPREFIX"ffmpeg" >/dev/null 2>&1
then
	echo -e $"\e[91mError:\e[0m ffmpeg could not be found."
	CONFIGERROR="x"
fi

### CHECK MODELS ###
if [ ! -d custom_nodes/ComfyUI-Manager ] && [ ! -d custom_nodes/ComfyUI-Manager-main ]; then
	echo -e $"\e[91mError:\e[0m ComfyUI-Manager could not be found. Install from \e[36mhttps://github.com/Comfy-Org/ComfyUI-Manager\e[0m"
	CONFIGERROR="x"
fi

if [ ! -d custom_nodes/comfyui_controlnet_aux ]; then
	echo -e $"\e[91mError:\e[0m Custom nodes comfyui_controlnet_aux could not be found. Use Custom Nodes Manager to install v1.1.0."
	CONFIGERROR="x"
fi
if [ ! -d custom_nodes/comfyui-videohelpersuite ]; then
	echo -e $"\e[91mError:\e[0m Custom nodes comfyui-videohelpersuite could not be found. Use Custom Nodes Manager to install v1.6.1."
	CONFIGERROR="x"
fi
if [ ! -d custom_nodes/bjornulf_custom_nodes ]; then
	echo -e $"\e[91mError:\e[0m Custom nodes bjornulf_custom_nodes could not be found. Use Custom Nodes Manager to install v1.1.8."
	CONFIGERROR="x"
fi
if [ ! -d custom_nodes/comfyui-easy-use ]; then
	echo -e $"\e[91mError:\e[0m Custom nodes comfyui-easy-use could not be found. Use Custom Nodes Manager to install v1.3.1."
	CONFIGERROR="x"
fi
if [ ! -d custom_nodes/comfyui-custom-scripts ]; then
	echo -e $"\e[91mError:\e[0m Custom nodes comfyui-custom-scripts could not be found. Use Custom Nodes Manager to install v1.2.5."
	CONFIGERROR="x"
fi
if [ ! -d custom_nodes/comfy-mtb ]; then
	echo -e $"\e[91mError:\e[0m Custom nodes comfy-mtb could not be found. Use Custom Nodes Manager to install v0.5.4."
	CONFIGERROR="x"
fi

### CHECK MODELS ###
if [ ! -e models/upscale_models/$UPSCALEMODELx4 ]; then
	echo -e $"\e[91mError:\e[0m Upscale model $UPSCALEMODELx4 could not be found in models/upscale_models. Use Model Manager to install."
	CONFIGERROR="x"
fi
if [ ! -e models/upscale_models/$UPSCALEMODELx2 ]; then
	echo -e $"\e[91mError:\e[0m Upscale model $UPSCALEMODELx2 could not be found in models/upscale_models. Use Model Manager to install."
	CONFIGERROR="x"
fi
SEARCHCOUNT_MODEL=`find $COMFYUIPATH/custom_nodes/comfyui_controlnet_aux/ckpts -name $DEPTH_MODEL_CKPT | wc -l`
if [[ $SEARCHCOUNT_MODEL -eq 0 ]] ; then
	if [ "$DEPTH_MODEL_CKPT" != "depth_anything_v2_vitl.pth" ] ; then
		echo -e $"\e[91mError:\e[0m Depth model $DEPTH_MODEL_CKPT could not be found in $COMFYUIPATH/custom_nodes/comfyui_controlnet_aux/ckpts"
		echo -e $"It must be installed manually. Spoiler: \e[36mhttps://www.reddit.com/r/comfyui/comments/1lchvqw/depth_anything_v2_giant/\e[0m"
		CONFIGERROR="x"
	else
		echo -e $"\e[94mInfo:\e[0m Depth model $DEPTH_MODEL_CKPT not yet downloaded by comfyui_controlnet_aux"
	fi
else
	
	if [ "$DEPTH_MODEL_CKPT" == "depth_anything_v2_vitl.pth" ] ; then
		if [ -e custom_nodes/comfyui_controlnet_aux/ckpts/depth-anything/Depth-Anything-V2-Giant ] ; then
			echo -e $"\e[94mInfo:\e[0m default depth model used, but Depth-Anything-V2-Giant detected!"
			echo -e $"  Consider to update \e[92mDEPTH_MODEL_CKPT=depth_anything_v2_vitg.pth\e[0m in \e[36m$CONFIGFILE\e[0m"
		else
			echo -e $"\e[94mInfo:\e[0m default depth model used. To use Depth-Anything-V2-Giant install it manually."
			echo -e $"  Then update DEPTH_MODEL_CKPT in \e[36m$CONFIGFILE\e[0m"
			echo -e $"  Spoiler: \e[36mhttps://www.reddit.com/r/comfyui/comments/1lchvqw/depth_anything_v2_giant/\e[0m"
		fi
	fi
fi

### EXIT IF CHECK FAILED ###
if [[ ! -z $CONFIGERROR ]]; then
	echo "Hint: You can use Control + Click on any links that appear."
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
	echo -e $"\e[2mHint: You can use Control + Click on any links that appear.\e[0m"
	echo "" 
	
	./custom_nodes/comfyui_stereoscopic/api/status.sh
	echo " "
	
	while true;
	do
		# happens every iteration since daemon is responsibe to initially create config and detect comfyui changes
		COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
		COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
		export COMFYUIHOST COMFYUIPORT

		# move output to next stage input
		mkdir -p input/vr/scaling input/vr/fullsbs
		# dubbing -> scaling
		GLOBIGNORE="*_x?*.mp4"
		mv -f output/vr/dubbing/*.mp4 input/vr/scaling  >/dev/null 2>&1
		# scaling -> fullsbs
		GLOBIGNORE="*_SBS_LR*.mp4"
		mv -f output/vr/scaling/*.mp4 output/vr/scaling/*.png output/vr/scaling/*.jpg output/vr/scaling/*.jpeg output/vr/scaling/*.PNG output/vr/scaling/*.JPG output/vr/scaling/*.JPEG input/vr/fullsbs  >/dev/null 2>&1
		unset GLOBIGNORE		

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
