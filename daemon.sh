#!/bin/sh
# Executes the whole SBS workbench pipeline again and again ...
# Copyright (c) 2025 Fortuna Cournot. MIT License.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../..`

cd $COMFYUIPATH

if [ ! -e "custom_nodes/comfyui_stereoscopic/.test" ] ; then
	echo -e $"\e[91mError:\e[0m Please start ComfyUI and complete installation."
	exit
fi

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini
if [ -e $CONFIGFILE ] ; then
	config_version=$(awk -F "=" '/config_version/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
	if [ $config_version -lt 2 ]; then
		mv -f -- $CONFIGFILE $CONFIGFILE-$config_version.bak
	fi
fi

if [ ! -e $CONFIGFILE ] ; then
	mkdir -p ./user/default/comfyui_stereoscopic
	touch "$CONFIGFILE"
	
	echo "# --- comfyui_stereoscopic config  ---">>"$CONFIGFILE"
	echo "config_version=2">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"
	
	echo "# Loglevel is not fully implemented overall yet.  -1 = quiet(very brief, but not silent). 0 = normal(briefer in future). 1 = verbose(like now). 2 = trace(set -x), keep intermediate. ">>"$CONFIGFILE"			
	echo "loglevel=0">>"$CONFIGFILE"			
	echo "">>"$CONFIGFILE"
	
	echo "# Set PIPELINE_AUTOFORWARD to 0 to disable it">>"$CONFIGFILE"
	echo "PIPELINE_AUTOFORWARD=1">>"$CONFIGFILE"
	
	echo "# --- comfyui server config ---">>"$CONFIGFILE"
	echo "COMFYUIHOST=127.0.0.1">>"$CONFIGFILE"
	echo "COMFYUIPORT=8188">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"

	echo "# --- sbs converter config ---">>"$CONFIGFILE"
	echo "# Depth-Effect Strengthness. Normalized, Values over 1 make it stronger, lower than 1 weaker.">>"$CONFIGFILE"
	echo "SBS_DEPTH_SCALE=1.25">>"$CONFIGFILE"
	echo "# Depth Placement. Normalized. Values over 0 make it appear closer, lower than 0 farer away. Absolute values higher than depth scale make it appear extremer.">>"$CONFIGFILE"
	echo "SBS_DEPTH_OFFSET=0.0">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"
	
	echo "# Used depth model by comfyui_controlnet_aux">>"$CONFIGFILE"
	if [ -e custom_nodes/comfyui_controlnet_aux/ckpts/depth-anything/Depth-Anything-V2-Giant ] ; then
		echo "DEPTH_MODEL_CKPT=depth_anything_v2_vitg.pth">>"$CONFIGFILE"
	else
		echo "# depth_anything_v2_vitg.pth installed ?">>"$CONFIGFILE"
		echo "DEPTH_MODEL_CKPT=depth_anything_v2_vitl.pth">>"$CONFIGFILE"
	fi
	echo "">>"$CONFIGFILE"
	
	echo "# --- video config ---">>"$CONFIGFILE"
	echo "# If not in systempath set ffmpeg path without trailing /">>"$CONFIGFILE"
	echo "FFMPEGPATHPREFIX=">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"
	
	echo "# Limits the framerate of video processing, has influence on memory consumption.">>"$CONFIGFILE"
	echo "MAXFPS=30">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"
	
	echo "# --- Video Output configuration. Not used everywhere yet. ---">>"$CONFIGFILE"
	echo "VIDEO_FORMAT=video/h264-mp4">>"$CONFIGFILE"
	echo "VIDEO_PIXFMT=yuv420p">>"$CONFIGFILE"
	echo "VIDEO_CRF=17">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"
	
	echo "# --- scaling config ---">>"$CONFIGFILE"
	echo "# x4 configuration">>"$CONFIGFILE"
	echo "UPSCALEMODELx4=RealESRGAN_x4plus.pth">>"$CONFIGFILE"
	echo "RESCALEx4=1.0">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"
	
	echo "# x2 configuration. x4 models need rescaling">>"$CONFIGFILE"
	echo "UPSCALEMODELx2=RealESRGAN_x4plus.pth">>"$CONFIGFILE"
	echo "RESCALEx2=0.5">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"
	
	echo "# percentage of Scaled AI image used against original input. Setting it to 1.0 will not use original input.">>"$CONFIGFILE"
	echo "SCALEBLENDFACTOR=0.9">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"
	
	echo "# Internal normalizing resolution for bluring.">>"$CONFIGFILE"
	echo "SCALESIGMARESOLUTION=1920.0">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"
	
	echo "# --- dubbing config ---">>"$CONFIGFILE"
	echo "FLORENCE2MODEL=microsoft/Florence-2-base">>"$CONFIGFILE"
	echo "SPLITSEGMENTTIME=1">>"$CONFIGFILE"
	echo "MAXDUBBINGSEGMENTTIME=64">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"

	mkdir -p input/vr/dubbing input/vr/downscale
	echo "PLACE FILES NOT HERE. PLACE THEM IN SUBFOLDERS PLEASE." >>input/vr/dubbing/DO_NOT_PLACE_HERE.TXT
	cp input/vr/dubbing/DO_NOT_PLACE_HERE.TXT input/vr/downscale/DO_NOT_PLACE_HERE.TXT

	if ! command -v ffmpeg >/dev/null 2>&1
	then
		echo -e $"\e[91mError:\e[0m ffmpeg could not be found in systempath."
		exit 1
	fi
fi

SHORT_CONFIGFILE=$CONFIGFILE
CONFIGFILE=`realpath "$CONFIGFILE"`
export CONFIGFILE

loglevel=$(awk -F "=" '/loglevel/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
[ $loglevel -ge 2 ] && set -x

[ $loglevel -ge 0 ] && echo -e $"\e[1mUsing $SHORT_CONFIGFILE\e[0m"
config_version=$(awk -F "=" '/config_version/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
PIPELINE_AUTOFORWARD=$(awk -F "=" '/PIPELINE_AUTOFORWARD/ {print $2}' $CONFIGFILE) ; PIPELINE_AUTOFORWARD=${PIPELINE_AUTOFORWARD:-1}
FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}
UPSCALEMODELx4=$(awk -F "=" '/UPSCALEMODELx4/ {print $2}' $CONFIGFILE) ; UPSCALEMODELx4=${UPSCALEMODELx4:-"RealESRGAN_x4plus.pth"}
UPSCALEMODELx2=$(awk -F "=" '/UPSCALEMODELx2/ {print $2}' $CONFIGFILE) ; UPSCALEMODELx2=${UPSCALEMODELx2:-"RealESRGAN_x4plus.pth"}
FLORENCE2MODEL=$(awk -F "=" '/FLORENCE2MODEL/ {print $2}' $CONFIGFILE) ; FLORENCE2MODEL=${FLORENCE2MODEL:-"microsoft/Florence-2-base"}
DEPTH_MODEL_CKPT=$(awk -F "=" '/DEPTH_MODEL_CKPT/ {print $2}' $CONFIGFILE) ; DEPTH_MODEL_CKPT=${DEPTH_MODEL_CKPT:-"depth_anything_v2_vitl.pth"}

CONFIGERROR=

# Upgrade config
if [ $config_version -le 2 ] ; then
	echo "# --- watermark config ---">>"$CONFIGFILE"
	echo "# watermark key . if you change watermark background (in user/default/comfyui_stereoscopic) you must change this key.">>"$CONFIGFILE"
	NEWSECRETKEY=`shuf -i 1-2000000000 -n 1`
	echo "WATERMARK_SECRETKEY=$NEWSECRETKEY">>"$CONFIGFILE"
	echo "# --- watermark label, e.g. author name (max. 17 characters, alphanumeric) ---">>"$CONFIGFILE"
	echo "# stop here --------------------v">>"$CONFIGFILE"
	echo "WATERMARK_LABEL=">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"

	echo "# --- metadata config ---">>"$CONFIGFILE"
	echo "# Path of the exiftool binary. If present exiftool is used for metadata management.">>"$CONFIGFILE"
	echo "EXIFTOOLBINARY="`which exiftool.exe 2>/dev/null` >>"$CONFIGFILE"
	echo "# metadata keys where generated descriptions are stored in:">>"$CONFIGFILE"
	echo "DESCRIPTION_GENERATION_CSKEYLIST=XPComment,iptc:Caption-Abstract">>"$CONFIGFILE"
	echo "# task of Florence2Run node:">>"$CONFIGFILE"
	echo "DESCRIPTION_FLORENCE_TASK=more_detailed_caption">>"$CONFIGFILE"
	echo "# metadata keys where generated ocr result is stored in:">>"$CONFIGFILE"
	echo "OCR_GENERATION_CSKEYLIST=Keywords,iptc:Keywords">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"
	
	cp ./custom_nodes/comfyui_stereoscopic/docs/img/watermark-background.png ./user/default/comfyui_stereoscopic/watermark_background.png
	
	sed -i "/^config_version=/s/=.*/=3/" $CONFIGFILE
	
	config_version=$(awk -F "=" '/config_version/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
fi

[ $loglevel -ge 0 ] && echo -e $"For processings read docs on \e[36mhttps://civitai.com/models/1757677\e[0m"
[ $loglevel -ge 0 ] && echo -e $"\e[2mHint: You can use Control + Click on any links that appear.\e[0m"


### CHECK TOOLS ###
if ! command -v $FFMPEGPATHPREFIX"ffmpeg" >/dev/null 2>&1
then
	echo -e $"\e[91mError:\e[0m ffmpeg could not be found."
	CONFIGERROR="x"
fi

### CHECK MODELS ###

if [ ! -d custom_nodes/comfyui_controlnet_aux ]; then
	echo -e $"\e[91mError:\e[0m Custom nodes comfyui_controlnet_aux could not be found. Use Custom Nodes Manager to install v1.1.0."
	CONFIGERROR="x"
fi
if [ ! -d custom_nodes/comfyui-videohelpersuite ]; then
	echo -e $"\e[91mError:\e[0m Custom nodes comfyui-videohelpersuite could not be found. Use Custom Nodes Manager to install v1.6.1."
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
			[ $loglevel -ge 0 ] && echo -e $"\e[94mInfo:\e[0m default depth model used, but Depth-Anything-V2-Giant detected!"
			[ $loglevel -ge 0 ] && echo -e $"  Consider to update \e[92mDEPTH_MODEL_CKPT=depth_anything_v2_vitg.pth\e[0m in \e[36m$CONFIGFILE\e[0m"
		else
			[ $loglevel -ge 0 ] && echo -e $"\e[94mInfo:\e[0m default depth model used. To use Depth-Anything-V2-Giant install it manually."
			[ $loglevel -ge 0 ] && echo -e $"  Then update DEPTH_MODEL_CKPT in \e[36m$CONFIGFILE\e[0m"
			[ $loglevel -ge 0 ] && echo -e $"  Spoiler: \e[36mhttps://www.reddit.com/r/comfyui/comments/1lchvqw/depth_anything_v2_giant/\e[0m"
		fi
	fi
fi

# CHECK TOOLS
EXIFTOOLBINARY=$(awk -F "=" '/EXIFTOOLBINARY/ {print $2}' $CONFIGFILE) ; EXIFTOOLBINARY=${EXIFTOOLBINARY:-""}
if [ ! -e "$EXIFTOOLBINARY" ]; then
	echo -e $"\e[94mInfo:\e[0m Tagging not available, Exif tool missing. Set path at \e[92mEXIFTOOLBINARY\e[0m in"
	echo -e $"\e[94m     \e[0m \e[36m$CONFIGFILE\e[0m"
	echo -e $"\e[94m     \e[0m You may download Exiftool by visiting \e[36mhttps://exiftool.org\e[0m"
elif [[ "$EXIFTOOLBINARY" =~ "(-k)" ]]; then
	echo -e $"\e[91mError:\e[0m Exif tool binary must be renamed. Strip '(-k)' from name and update path at \e[92mEXIFTOOLBINARY\e[0m in"
	echo -e $"\e[91m      \e[0m \e[36m$CONFIGFILE\e[0m"
	exit
fi

# CHECK FOR VERSION UPDATE
if [ -e "custom_nodes/comfyui_stereoscopic/.test/.install" ] ; then
	./custom_nodes/comfyui_stereoscopic/tests/run_tests.sh
	if [ -e "custom_nodes/comfyui_stereoscopic/.test/.install" ] ; then
		echo -e $"\e[91mError:\e[0m Tests failed."
		exit
	fi
fi

### EXIT IF CHECK FAILED ###
if [[ ! -z $CONFIGERROR ]]; then
	[ $loglevel -ge 0 ] && echo "Hint: You can use Control + Click on any links that appear."
	exit
fi


columns=$(tput cols)

CONFIGPATH=user/default/comfyui_stereoscopic
POSITIVESFXPATH="$CONFIGPATH/dubbing_sfx_positive.txt"
NEGATIVESFXPATH="$CONFIGPATH/dubbing_sfx_negative.txt"
if [ ! -e "$POSITIVESFXPATH" ]
then
	mkdir -p $CONFIGPATH
	echo "" >$POSITIVESFXPATH
fi
if [ ! -e "$NEGATIVEPSFXATH" ]
then
	mkdir -p $CONFIGPATH
	echo "music, voice, crying, squeaking." >$NEGATIVESFXPATH
fi


if test $# -ne 0
then
	# targetprefix path is relative; parent directories are created as needed
	echo "Usage: $0 "
	echo "E.g.: $0 "
else
	mkdir -p input/vr/slideshow input/vr/dubbing/sfx input/vr/scaling input/vr/fullsbs input/vr/scaling/override input/vr/singleloop input/vr/slides input/vr/concat input/vr/downscale/4K input/vr/caption
	SERVERERROR=
	
	if [ -e custom_nodes/comfyui_stereoscopic/pyproject.toml ]; then
		VERSION=`cat custom_nodes/comfyui_stereoscopic/pyproject.toml | grep "version = " | grep -v "minversion" | grep -v "target-version"`
	else
		echo -e $"\e[91mError:\e[0m script not started in ComfyUI folder!"
		exit
	fi

	echo ""
	[ $loglevel -ge 0 ] && echo -e $"\e[97m\e[1mStereoscopic Pipeline Processing started. $VERSION\e[0m"
	[ $loglevel -ge 0 ] && echo -e $"\e[2m"
	[ $loglevel -ge 0 ] && echo "Waiting for your files to be placed in folders:"

	### CHECK FOR OPTIONAL NODE PACKAGES AND OTHER PROBLEMS ###
	if [ ! -d custom_nodes/comfyui-florence2 ]; then
		[ $loglevel -ge 0 ] && echo -e $"\e[93mWarning:\e[0m Custom nodes ComfyUI-Florence2 could not be found. Use Custom Nodes Manager to install v1.0.5."
		CONFIGERROR="x"
	fi
	if [ ! -d custom_nodes/comfyui-mmaudio ] ; then
		[ $loglevel -ge 0 ] && echo -e $"\e[93mWarning:\e[0m Custom nodes ComfyUI-MMAudio could not be found. Use Custom Nodes Manager to install v1.0.2."
		CONFIGERROR="x"
	fi
	[ $columns -lt 100 ] &&	CONFIGERROR="x"  && echo -e $"\e[93mWarning:\e[0m Shell windows has less than 100 columns. Got to options - Window and increate it."

	[ $loglevel -ge 0 ] && echo "" 
	./custom_nodes/comfyui_stereoscopic/api/status.sh
	[ $loglevel -ge 0 ] && echo " "
	
	INITIALRUN=TRUE
	while true;
	do
		# happens every iteration since daemon is responsibe to initially create config and detect comfyui changes
		COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
		COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
		export COMFYUIHOST COMFYUIPORT

		[ $loglevel -ge 0 ] && [[ ! -z "$INITIALRUN" ]] && echo "Using ComfyUI on $COMFYUIHOST port $COMFYUIPORT" && INITIALRUN=

		# GLOBAL: move output to next stage input (This must happen in batch_all per stage, too)
		mkdir -p input/vr/scaling input/vr/fullsbs
		# scaling -> fullsbs
		GLOBIGNORE="*_SBS_LR*.*"
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && mv -f -- output/vr/scaling/*.mp4 output/vr/scaling/*.png output/vr/scaling/*.jpg output/vr/scaling/*.jpeg output/vr/scaling/*.PNG output/vr/scaling/*.JPG output/vr/scaling/*.JPEG input/vr/fullsbs output/vr/scaling/*.webm output/vr/scaling/*.WEBM input/vr/fullsbs  >/dev/null 2>&1
		# slides -> fullsbs
		GLOBIGNORE="*_SBS_LR*.*"
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && mv -f -- output/vr/slides/*.* input/vr/fullsbs  >/dev/null 2>&1
		# dubbing -> scaling
		#GLOBIGNORE="*_x?*.mp4"
		#[ $PIPELINE_AUTOFORWARD -ge 1 ] && mv -f -- output/vr/dubbing/sfx/*.mp4 input/vr/scaling  >/dev/null 2>&1
		
		unset GLOBIGNORE		

		# FAILSAFE
		mv -f -- input/vr/fullsbs/*_SBS_LR*.* output/vr/fullsbs  >/dev/null 2>&1
		
		status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
		if [ "$status" = "closed" ]; then
			echo -ne $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT\r"
			SERVERERROR="x"
		else
			if [[ ! -z $SERVERERROR ]]; then
				[ $loglevel -ge 0 ] && echo ""
				SERVERERROR=
			fi
			
			SLIDECOUNT=`find input/vr/slides -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' -o -name '*.webm' -o -name '*.WEBM' | wc -l`
			SLIDESBSCOUNT=`find input/vr/slideshow -maxdepth 1 -type f -name '*.png' | wc -l`
			DUBSFXCOUNT=`find input/vr/dubbing/sfx -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' | wc -l`
			SCALECOUNT=`find input/vr/scaling -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' -o -name '*.WEBM' -o -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
			SBSCOUNT=`find input/vr/fullsbs -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' -o -name '*.WEBM' -o -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
			OVERRIDECOUNT=`find input/vr/scaling/override -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' -o -name '*.WEBM' -o -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
			SINGLELOOPCOUNT=`find input/vr/singleloop -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' | wc -l`
			CONCATCOUNT=`find input/vr/concat -maxdepth 1 -type f -name '*.mp4' | wc -l`
			WMECOUNT=`find input/vr/watermark/encrypt -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
			WMDCOUNT=`find input/vr/watermark/decrypt -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
			CAPCOUNT=`find input/vr/caption -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
			
			if [ $WMECOUNT -gt 0 ] ; then
				WATERMARK_LABEL=$(awk -F "=" '/WATERMARK_LABEL/ {print $2}' $CONFIGFILE) ; WATERMARK_LABEL=${WATERMARK_LABEL:-""}
				if [[ -z $WATERMARK_LABEL ]] ; then
					echo -e $"\e[91mError:\e[0m You must configure WATERMARK_LABEL in $CONFIGFILE to encrypt. exiting."
					exit
				fi
			fi
			
			COUNT=$(( DUBSFXCOUNT + SCALECOUNT + SBSCOUNT + OVERRIDECOUNT + SINGLELOOPCOUNT + CONCATCOUNT + WMECOUNT + WMDCOUNT + CAPCOUNT ))
			COUNTWSLIDES=$(( SLIDECOUNT + $COUNT ))
			COUNTSBSSLIDES=$(( SLIDESBSCOUNT + $COUNT ))
			if [[ $COUNT -gt 0 ]] || [[ $SLIDECOUNT -gt 1 ]] || [[ $COUNTSBSSLIDES -gt 1 ]] ; then
				[ $loglevel -ge 0 ] && echo "Found $COUNT files in incoming folders:"
				[ $loglevel -ge 0 ] && echo "$SLIDECOUNT slides , $SCALECOUNT + $OVERRIDECOUNT to scale >> $SBSCOUNT for sbs >> $SINGLELOOPCOUNT to loop, $SLIDECOUNT for slideshow >> $CONCATCOUNT to concat" && echo "$DUBSFXCOUNT to dub, $WMECOUNT to encrypt, $WMDCOUNT to decrypt, $CAPCOUNT for caption"
				sleep 1
				./custom_nodes/comfyui_stereoscopic/api/batch_all.sh
				[ $loglevel -ge 0 ] && echo "****************************************************"
				[ $loglevel -ge 0 ] && echo "Using ComfyUI on $COMFYUIHOST port $COMFYUIPORT"
				
				./custom_nodes/comfyui_stereoscopic/api/status.sh				
				[ $loglevel -ge 0 ] && echo " "
			else
				BLINK=`shuf -n1 -e "..." "   "`
				[ $loglevel -ge 0 ] && echo -ne $"\e[2mWaiting for new files$BLINK\e[0m     \r"
				sleep 1
			fi
		fi
		
		DOWNSCALECOUNT=`find input/vr/downscale/4K -maxdepth 1 -type f -name '*.mp4' | wc -l`
		if [[ $DOWNSCALECOUNT -gt 0 ]]; then
			./custom_nodes/comfyui_stereoscopic/api/batch_downscale.sh
		fi

	done #KILL ME
fi
[ $loglevel -ge 0 ] && set +x
