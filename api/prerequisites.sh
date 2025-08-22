#!/bin/sh
# Executes the whole SBS workbench pipeline again and again ...
# Copyright (c) 2025 Fortuna Cournot. MIT License.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`

cd $COMFYUIPATH

if [ ! -e "custom_nodes/comfyui_stereoscopic/.test" ] ; then
	echo -e $"\e[91mError:\e[0m Please start ComfyUI and complete installation."
	exit 1
fi

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini
if [ -e $CONFIGFILE ] ; then
	config_version=$(awk -F "=" '/config_version/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
	if [ $config_version -lt 4 ]; then
		mv -f -- $CONFIGFILE $CONFIGFILE-$config_version.bak
	fi
fi

if [ ! -e $CONFIGFILE ] ; then
	mkdir -p ./user/default/comfyui_stereoscopic
	touch "$CONFIGFILE"
	
	echo "# --- comfyui_stereoscopic config  ---">>"$CONFIGFILE"
	echo "# Warning: Simple syntax. inline comments are not supported.">>"$CONFIGFILE"
	echo "config_version=4">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"
	
	echo "# Loglevel is not fully implemented overall yet.  -1 = quiet(very brief, but not silent). 0 = normal(briefer in future). 1 = verbose(like now). 2 = trace(set -x), keep intermediate. ">>"$CONFIGFILE"			
	echo "loglevel=0">>"$CONFIGFILE"			
	echo "">>"$CONFIGFILE"
	
	echo "# Set PIPELINE_AUTOFORWARD to 1 to enable it">>"$CONFIGFILE"
	echo "PIPELINE_AUTOFORWARD=0">>"$CONFIGFILE"
	
	echo "# --- comfyui server config ---">>"$CONFIGFILE"
	echo "COMFYUIHOST=127.0.0.1">>"$CONFIGFILE"
	echo "COMFYUIPORT=8188">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"

	echo "# --- sbs converter config ---">>"$CONFIGFILE"
	echo "# Depth-Effect Strengthness. Normalized, Values over 1 make it stronger, lower than 1 weaker.">>"$CONFIGFILE"
	echo "SBS_DEPTH_SCALE=1.25">>"$CONFIGFILE"
	echo "# Depth Placement. Normalized. Values over 0 make it appear closer, lower than 0 farer away. Absolute values higher than depth scale make it appear extremer.">>"$CONFIGFILE"
	echo "SBS_DEPTH_OFFSET=0.0">>"$CONFIGFILE"
	echo "# To reduce artifacts increase value for cost of depth detail quality. Number must be odd, between 1 and 99. -1 turns off. ">>"$CONFIGFILE"
	echo "SBS_DEPTH_BLUR_RADIUS=19">>"$CONFIGFILE"
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
	echo "# x4 scaling upper limit pixels">>"$CONFIGFILE"
	echo "LIMIT4X_NORMAL=518400">>"$CONFIGFILE"
	echo "# x2 scaling upper limit pixels">>"$CONFIGFILE"
	echo "LIMIT2X_NORMAL=2073600">>"$CONFIGFILE"
	echo "# x4 scaling upper limit pixels for substage override">>"$CONFIGFILE"
	echo "LIMIT4X_OVERRIDE=1036800">>"$CONFIGFILE"
	echo "# x2 scaling upper limit pixels for substage override when 60s+ duration">>"$CONFIGFILE"
	echo "LIMIT2X_OVERRIDE_LONG=4147200">>"$CONFIGFILE"
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
	echo "">>"$CONFIGFILE"

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
	echo "# metadata keys where generated title are stored in: e.g. XMP:Title,EXIF:ImageDescription,IPTC:Caption-Abstract,XMP:Description,EXIF:XPTitle">>"$CONFIGFILE"
	echo "TITLE_GENERATION_CSKEYLIST=XMP:Title">>"$CONFIGFILE"
	echo "# image metadata keys where generated title is stored in, e.g. comment,XMP-exif:UserComment">>"$CONFIGFILE"
	echo "DESCRIPTION_GENERATION_CSKEYLIST=comment,XMP-exif:UserComment">>"$CONFIGFILE"
	echo "# task of Florence2Run node: detailed_caption or more_detailed_caption">>"$CONFIGFILE"
	echo "DESCRIPTION_FLORENCE_TASK=more_detailed_caption">>"$CONFIGFILE"
	echo "# metadata keys where generated ocr result is stored in:">>"$CONFIGFILE"
	echo "OCR_GENERATION_CSKEYLIST=iptc:Keywords">>"$CONFIGFILE"
	echo "# metadata key seperator:">>"$CONFIGFILE"
	echo "OCR_GENERATION_KEYSEP=,">>"$CONFIGFILE"	
	echo "# Target language locale of the description. Set empty to deactivate translation (keep english):">>"$CONFIGFILE"
	echo "DESCRIPTION_LOCALE="`locale -u`>>"$CONFIGFILE"
	echo "# 3-ditit ISO 639-2 code used for subtitle language . has to be changed manually by user:">>"$CONFIGFILE"
	echo "ISO_639_2_CODE=eng">>"$CONFIGFILE"
	echo "# Caption Stage image strip off key list, e.g.: Prompt,Workflow,UserComment">>"$CONFIGFILE"
	echo "EXIF_PURGE_CSKEYLIST=Prompt,Workflow,UserComment" >>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"
 

	cp ./custom_nodes/comfyui_stereoscopic/docs/img/watermark-background.png ./user/default/comfyui_stereoscopic/watermark_background.png

	mkdir -p input/vr/dubbing input/vr/downscale

	mkdir -p input/vr/singleloop/error 


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

# Delta Upgrade config to version 5
NEXTUPGRADESTEPVERSION=5
if [ $config_version -lt $NEXTUPGRADESTEPVERSION ] ; then
	echo "Upgrading config.ini from v$config_version to v$NEXTUPGRADESTEPVERSION"

	echo "# --- TVAI config ---">>"$CONFIGFILE"

	# Check windows default path for default
	echo "# Path of the Topaz Video AI (v6 + v7) software. If present Video AI software is used for the video scaling stage.">>"$CONFIGFILE"
	if [ -e  '/c/Program Files/Topaz Labs LLC/Topaz Video AI/ffmpeg.exe' ] ; then
		echo "TVAI_BIN_DIR=/c/Program Files/Topaz Labs LLC/Topaz Video AI" >>"$CONFIGFILE"
	else
		echo "TVAI_BIN_DIR=" >>"$CONFIGFILE"
	fi

	echo "# Path to the Topaz Video AI models. Refer to manual">>"$CONFIGFILE"
	if [ -e  '$TVAI_MODEL_DATA_DIR' ] && [ -e  '$TVAI_MODEL_DIR' ] ; then
		echo "TVAI_MODEL_DATA_DIR=$TVAI_MODEL_DATA_DIR" >>"$CONFIGFILE"
		echo "TVAI_MODEL_DIR=$TVAI_MODEL_DIR" >>"$CONFIGFILE"
	elif [ -e  '/c/ProgramData/Topaz Labs LLC/Topaz Video AI/models' ] ; then
		echo "TVAI_MODEL_DATA_DIR=/c/ProgramData/Topaz Labs LLC/Topaz Video AI/models" >>"$CONFIGFILE"
		echo "TVAI_MODEL_DIR=/c/ProgramData/Topaz Labs LLC/Topaz Video AI/models" >>"$CONFIGFILE"
	else
		echo "TVAI_MODEL_DATA_DIR=" >>"$CONFIGFILE"
		echo "TVAI_MODEL_DIR=" >>"$CONFIGFILE"
	fi
	
	echo "# TVAI Filter String. Ensure the model json, here prob-4, is existing in TVAI_MODEL_DIR. better for portrait: iris-2">>"$CONFIGFILE"
	echo "TVAI_FILTER_STRING_UP4X=tvai_up=model=prob-4:scale=4:recoverOriginalDetailValue=0:preblur=0:noise=0:details=0:halo=0:blur=0:compression=0:estimate=8:blend=0.2:device=0:vram=1:instances=1"
	echo "TVAI_FILTER_STRING_UP2X=tvai_up=model=prob-4:scale=2:recoverOriginalDetailValue=0:preblur=0:noise=0:details=0:halo=0:blur=0:compression=0:estimate=8:blend=0.2:device=0:vram=1:instances=1"
	echo "">>"$CONFIGFILE"

	echo "# --- dubbing config update ---">>"$CONFIGFILE"
	echo "# Videos with durations below above this threshold will be segmented.">>"$CONFIGFILE"
	echo "DUBBINGSEGMENTTING_THRESHOLD=20">>"$CONFIGFILE"
	echo "# Segment Duration. should be same as slide duration (including transition) for slideshows dubbing.">>"$CONFIGFILE"
	echo "DUBBINGSEGMENTTIME=5">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"

	sed -i "/^config_version=/s/=.*/="$NEXTUPGRADESTEPVERSION"/" $CONFIGFILE
	echo "">>"$CONFIGFILE"
	
	config_version=$(awk -F "=" '/config_version/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
	echo "Upgraded config.ini to v$config_version"
fi


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
	exit 1
fi


CONFIGPATH=user/default/comfyui_stereoscopic
if [ ! -e "$CONFIGPATH" ]
then
	mkdir -p $CONFIGPATH
fi


# prepare tasks
taskdefinitions=`ls custom_nodes/comfyui_stereoscopic/config/tasks/*.json`
for task in $taskdefinitions ; do
	taskname=${task##*/}
	taskname=${taskname%.json}
	version=`cat "$task" | grep -o '"version":[^"]*"[^"]*"' | sed -E 's/".*".*"(.*)"/\1/'`
	if [ $version -eq 1 ] ; then
		mkdir -p input/vr/tasks/$taskname output/vr/tasks/$taskname
	fi
done
if [ ! -e "$CONFIGPATH"/tasks ]
then
	mkdir -p "$CONFIGPATH"/tasks
fi
taskdefinitions=`ls "$CONFIGPATH"/tasks/*.json 2>/dev/null` 
for task in $taskdefinitions ; do
	taskname=${task##*/}
	taskname=${taskname%.json}
	taskname=${taskname//[^[:alnum:].-]/_}
	taskname=${taskname// /_}
	taskname=${taskname//\(/_}
	taskname=${taskname//\)/_}
	version=`cat "$task" | grep -o '"version":[^"]*"[^"]*"' | sed -E 's/".*".*"(.*)"/\1/'`
	if [ $version -eq 1 ] ; then
		mkdir -p input/vr/tasks/"_"$taskname output/vr/tasks/"_"$taskname
	fi
done

# PLACE HINT FILES
echo "PLACE FILES NOT HERE. PLACE THEM IN SUBFOLDERS PLEASE." >input/vr/dubbing/DO_NOT_PLACE_HERE.TXT
cp input/vr/dubbing/DO_NOT_PLACE_HERE.TXT input/vr/downscale/DO_NOT_PLACE_HERE.TXT
cp input/vr/dubbing/DO_NOT_PLACE_HERE.TXT input/vr/tasks/DO_NOT_PLACE_HERE.TXT
mkdir -p input/vr/singleloop/error
echo "Repair files with a tool like avidemux. You need just to load it, then save it again as mp4 (muxer) with video codec x264." >input/vr/singleloop/error/CONSIDER_REPAIRING


# CHECK FOR VERSION UPDATE AND RUN TESTS
if [ -e "custom_nodes/comfyui_stereoscopic/.test/.install" ] ; then
	./custom_nodes/comfyui_stereoscopic/tests/run_tests.sh || exit 1
	if [ -e "custom_nodes/comfyui_stereoscopic/.test/.install" ] ; then
		echo -e $"\e[91mError:\e[0m Tests failed."
		exit 1
	fi
fi

POSITIVESFXPATH="$CONFIGPATH/dubbing_sfx_positive.txt"
NEGATIVESFXPATH="$CONFIGPATH/dubbing_sfx_negative.txt"
if [ ! -e "$POSITIVESFXPATH" ]
then
	echo "" >$POSITIVESFXPATH
fi
if [ ! -e "$NEGATIVEPSFXATH" ]
then
	echo "music, voice, crying, squeaking." >$NEGATIVESFXPATH
fi

[ $loglevel -ge 0 ] && echo -e $"For processings read docs on \e[36mhttps://civitai.com/models/1757677\e[0m"
[ $loglevel -ge 0 ] && echo -e $"\e[2mHint: You can use Control + Click on any links that appear.\e[0m"


### EXIT IF CHECK FAILED ###
if [[ ! -z $CONFIGERROR ]]; then
	exit 1
fi

exit 0
