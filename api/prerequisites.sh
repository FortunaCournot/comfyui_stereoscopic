#!/bin/sh
# Executes the whole SBS workbench pipeline again and again ...
# Copyright (c) 2025 Fortuna Cournot. MIT License.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`

cd $COMFYUIPATH

CONFIG_VERSION=10

rm -f "custom_nodes/comfyui_stereoscopic/.test/.signalfail" >/dev/null

if [ ! -e "custom_nodes/comfyui_stereoscopic/.test" ] ; then
	echo -e $"\e[96mInfo:\e[0m Waiting for ComfyUI to complete installation..."
	while [ ! -e "custom_nodes/comfyui_stereoscopic/.test" ] ; do
		sleep 1
	done
fi

# Use Systempath for python by default, but set it explictly for comfyui portable.
PYTHON_BIN_PATH=
if [ -d "../python_embeded" ]; then
  PYTHON_BIN_PATH=../python_embeded/
fi

node_dependencies=`cat custom_nodes/comfyui_stereoscopic/node_dependencies.txt`
for dependency in $node_dependencies ; do
	if [ ! -z "$dependency" ] ; then
			nodes="${dependency%=*}"
			minimum_version="${dependency#*\=}"
			if [ -e "custom_nodes/""$nodes""/pyproject.toml" ] ; then
				v=`grep "^version" custom_nodes/"$nodes"/pyproject.toml` ; v=${v#*\"} ; current_version="${v%\"*}"
				v1_min=${minimum_version%%\.*}
				v1_cur=${current_version%%\.*}
				v2_min=${minimum_version%\.*} ; v2_min=${v2_min#*\.}
				v2_cur=${current_version%\.*} ; v2_cur=${v2_cur#*\.}
				v3_min=${minimum_version##*\.} ; v3_min=${v3_min%[^0-9]*} 
				v3_cur=${current_version##*\.} ; v3_cur=${v3_cur%[^0-9]*} 
				if [ "$v1_cur" -gt "$v1_min" ] ; then
					continue
				elif [ "$v1_cur" -eq "$v1_min" ] && [ "$v2_cur" -gt "$v2_min" ] ; then
					continue
				elif [ "$v1_cur" -eq "$v1_min" ] && [ "$v2_cur" -eq "$v2_min" ] && [ "$v3_cur" -ge "$v3_min" ] ; then
					continue
				else
					echo -e $"\e[91mError:\e[0m Custom nodes $nodes version ($current_version) to low. Please upgrade to $minimum_version."
					rm -f user/default/comfyui_stereoscopic/.daemonactive
					exit 1
				fi
			else
				echo ""
				echo -e $"\e[91mError:\e[0m Custom nodes $nodes not found. Please install version $minimum_version."
				rm -f user/default/comfyui_stereoscopic/.daemonactive
				exit 1
			fi
	fi
done
 

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini
if [ -e $CONFIGFILE ] ; then
	config_version=$(awk -F "=" '/config_version=/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
	if [ $config_version -lt $CONFIG_VERSION ]; then
		mv -f -- $CONFIGFILE $CONFIGFILE-$config_version.bak
	fi
fi
if [ -e ./user/default/comfyui_stereoscopic/.installprofile ] ; then
    source ./user/default/comfyui_stereoscopic/.installprofile
fi
if [ ! -e $CONFIGFILE ] ; then
	mkdir -p ./user/default/comfyui_stereoscopic
	touch "$CONFIGFILE"
	
	echo "# --- comfyui_stereoscopic config  ---">>"$CONFIGFILE"
	echo "# if you delete this file it will be recreated on next start of the daemon."  >>"$CONFIGFILE"
	echo "# Warning: Simple syntax. inline comments are not supported.">>"$CONFIGFILE"
	echo "config_version=$CONFIG_VERSION">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"
	
	echo "# Loglevel is not fully implemented overall yet.  -1 = quiet(very brief, but not silent). 0 = normal(briefer in future). 1 = verbose(like now). 2 = trace(set -x), keep intermediate. ">>"$CONFIGFILE"			
	echo "loglevel=0">>"$CONFIGFILE"			
	echo "">>"$CONFIGFILE"
	
	echo "# Set PIPELINE_AUTOFORWARD to 1 to enable it">>"$CONFIGFILE"
	echo "PIPELINE_AUTOFORWARD=1">>"$CONFIGFILE"
	echo "# Set DEBUG_AUTOFORWARD_RULES to 1 to debug rules">>"$CONFIGFILE"
	echo "DEBUG_AUTOFORWARD_RULES=0">>"$CONFIGFILE"
	
	echo "">>"$CONFIGFILE"
	
	echo "# --- comfyui server config ---">>"$CONFIGFILE"
	echo "COMFYUIHOST=127.0.0.1">>"$CONFIGFILE"
	echo "COMFYUIPORT=8188">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"

	echo "# --- Language settings ---">>"$CONFIGFILE"
	echo "# Target language locale of the description. Set empty to deactivate translation (keep english):">>"$CONFIGFILE"
	echo "DESCRIPTION_LOCALE="`locale -u`>>"$CONFIGFILE"
	echo "# 3-ditit ISO 639-2 code used for subtitle language . has to be changed manually by user:">>"$CONFIGFILE"
	echo "ISO_639_2_CODE=eng">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"

	echo "# --- sbs converter config ---">>"$CONFIGFILE"
	echo "# Depth-Effect Strengthness. Normalized, Values over 1 make it stronger, lower than 1 weaker.">>"$CONFIGFILE"
	echo "SBS_DEPTH_SCALE=1.0">>"$CONFIGFILE"
	echo "# Depth Placement. Normalized. Values over 0 make it appear closer, lower than 0 farer away. Absolute values higher than depth scale make it appear extremer.">>"$CONFIGFILE"
	echo "SBS_DEPTH_OFFSET=0.0">>"$CONFIGFILE"
	echo "# To reduce artifacts increase value for cost of depth detail quality. Number must be odd, between 1 and 99. -1 turns off. ">>"$CONFIGFILE"
	echo "SBS_DEPTH_BLUR_RADIUS_VIDEO=19">>"$CONFIGFILE"
	echo "# To reduce artifacts increase value for cost of depth detail quality. Number must be odd, between 1 and 99. -1 turns off. ">>"$CONFIGFILE"
	echo "SBS_DEPTH_BLUR_RADIUS_IMAGE=19">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"
	
	if [ -e "/c/Windows/System32/nvidia-smi.exe" ] ; then
		echo "# Used depth model by comfyui-depthanythingv2 (GPU detected)">>"$CONFIGFILE"
		echo "DEPTH_MODEL_CKPT=depth_anything_v2_vitb_fp16.safetensors">>"$CONFIGFILE"
		echo "DEPTH_RESOLUTION=1024">>"$CONFIGFILE"
	else
		echo "# Used depth model by comfyui-depthanythingv2 (no GPU detected)">>"$CONFIGFILE"
		echo "DEPTH_MODEL_CKPT=depth_anything_v2_vits_fp16.safetensors">>"$CONFIGFILE"
		echo "DEPTH_RESOLUTION=256">>"$CONFIGFILE"
	fi
	echo "">>"$CONFIGFILE"
	
	echo "# --- video config ---">>"$CONFIGFILE"
	echo "# If not in systempath set ffmpeg path without trailing /">>"$CONFIGFILE"
	echo "FFMPEGPATHPREFIX=">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"
	
	echo "# Limits the framerate of video processing (double WAN2.2), has influence on memory consumption.">>"$CONFIGFILE"
	echo "MAXFPS=32">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"
	
	echo "# --- Video Output configuration. Not used everywhere yet. ---">>"$CONFIGFILE"
	echo "VIDEO_FORMAT=video/h264-mp4">>"$CONFIGFILE"
	echo "VIDEO_PIXFMT=yuv420p">>"$CONFIGFILE"
	echo "VIDEO_CRF=17">>"$CONFIGFILE"
	echo "# --- CLI  (true/false) ---">>"$CONFIGFILE"
	echo "CLI_ENABLED=true">>"$CONFIGFILE"
	echo "# --- CLI Video Output quality: low, medium or high ---">>"$CONFIGFILE"
	echo "VIDEOQUALITYPRESET=high">>"$CONFIGFILE"
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
	echo "# x2 scaling upper limit pixels for substage override when 600s+ duration">>"$CONFIGFILE"
	echo "LIMIT2X_OVERRIDE_LONG=4147200">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"
	
	echo "# x2 configuration. x4 models need rescaling">>"$CONFIGFILE"
	echo "UPSCALEMODELx2=RealESRGAN_x2plus.pth">>"$CONFIGFILE"
	echo "RESCALEx2=1.0">>"$CONFIGFILE"
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
	echo "# Videos with durations below above this threshold will be segmented.">>"$CONFIGFILE"
	echo "DUBBINGSEGMENTTING_THRESHOLD=20">>"$CONFIGFILE"
	echo "# Segment Duration. should be same as slide duration (including transition) for slideshows dubbing.">>"$CONFIGFILE"
	echo "DUBBINGSEGMENTTIME_DURATION=5">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"

	echo "# --- watermark config ---">>"$CONFIGFILE"
	echo "# watermark key . if you change watermark background (in user/default/comfyui_stereoscopic) you must change this key.">>"$CONFIGFILE"
	NEWSECRETKEY=`shuf -i 1-2000000000 -n 1`
	echo "WATERMARK_SECRETKEY=$NEWSECRETKEY">>"$CONFIGFILE"
	echo "# --- watermark label, e.g. author name (max. 17 characters, alphanumeric) ---">>"$CONFIGFILE"
	echo "# stop here --------------------v">>"$CONFIGFILE"
	echo "WATERMARK_LABEL=3D-GALLERY.ORG">>"$CONFIGFILE"
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
	echo "# Caption Stage image strip off key list, e.g.: Prompt,Workflow,UserComment">>"$CONFIGFILE"
	echo "EXIF_PURGE_CSKEYLIST=Prompt,Workflow,UserComment" >>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"
 
 
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
	
	echo "# TVAI Upscale Filter String. Ensure the model json, here prob-4, is existing in TVAI_MODEL_DIR. better for portrait: iris-2">>"$CONFIGFILE"
	echo "# Documentation available by calling 'TVAI_BIN_DIR/ffmpeg.exe' -hide_banner -h filter=tvai_up">>"$CONFIGFILE"
	echo "TVAI_FILTER_STRING_UP4X=tvai_up=model=prob-4:scale=4:preblur=0:noise=0:details=0:halo=0:blur=0:compression=0:estimate=8:blend=0.0:device=0:vram=0.8:instances=1">>"$CONFIGFILE"
	echo "TVAI_FILTER_STRING_UP2X=tvai_up=model=prob-4:scale=2:preblur=0:noise=0:details=0:halo=0:blur=0:compression=0:estimate=8:blend=0.0:device=0:vram=0.8:instances=1">>"$CONFIGFILE"
	echo "# TVAI Interpolate Filter String; MUST END WITH ':fps=', target fps is calculated. Ensure the model json, here chf-3, is existing in TVAI MODEL DIR.">>"$CONFIGFILE"
	echo "# Documentation available by calling 'TVAI_BIN_DIR/ffmpeg.exe' -hide_banner -h filter=tvai_fi">>"$CONFIGFILE"
	echo "TVAI_FILTER_STRING_IP=tvai_fi=model=chf-3:slowmo=1:rdt=-0.000001:device=0:vram=0.8:instances=1:fps=">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"

	echo "# --- VR we are App config ---">>"$CONFIGFILE"
	echo "SCENEDETECTION_INPUTLENGTHLIMIT=20.0">>"$CONFIGFILE"
	echo "SCENEDETECTION_THRESHOLD_DEFAULT=0.1">>"$CONFIGFILE"
	echo "UML_FONTSIZE=11">>"$CONFIGFILE"
	echo "">>"$CONFIGFILE"

	cp ./custom_nodes/comfyui_stereoscopic/docs/img/watermark-background.png ./user/default/comfyui_stereoscopic/watermark_background.png

	mkdir -p input/vr/dubbing

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

loglevel=$(awk -F "=" '/loglevel=/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
[ $loglevel -ge 2 ] && set -x

[ $loglevel -ge 0 ] && echo -e $"\e[2mUsing \e[36m$CONFIGFILE\e[0m"
config_version=$(awk -F "=" '/config_version=/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
PIPELINE_AUTOFORWARD=$(awk -F "=" '/PIPELINE_AUTOFORWARD=/ {print $2}' $CONFIGFILE) ; PIPELINE_AUTOFORWARD=${PIPELINE_AUTOFORWARD:-1}
FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX=/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}
UPSCALEMODELx4=$(awk -F "=" '/UPSCALEMODELx4=/ {print $2}' $CONFIGFILE) ; UPSCALEMODELx4=${UPSCALEMODELx4:-"RealESRGAN_x4plus.pth"}
UPSCALEMODELx2=$(awk -F "=" '/UPSCALEMODELx2=/ {print $2}' $CONFIGFILE) ; UPSCALEMODELx2=${UPSCALEMODELx2:-"RealESRGAN_x4plus.pth"}
FLORENCE2MODEL=$(awk -F "=" '/FLORENCE2MODEL=/ {print $2}' $CONFIGFILE) ; FLORENCE2MODEL=${FLORENCE2MODEL:-"microsoft/Florence-2-base"}
DEPTH_MODEL_CKPT=$(awk -F "=" '/DEPTH_MODEL_CKPT=/ {print $2}' $CONFIGFILE) ; DEPTH_MODEL_CKPT=${DEPTH_MODEL_CKPT:-"depth_anything_v2_vitl.pth"}

CONFIGERROR=

# Delta Upgrade config to version 6
#NEXTUPGRADESTEPVERSION=7
#if [ $config_version -lt $NEXTUPGRADESTEPVERSION ] ; then
#	sed -i "/^config_version=/s/=.*/="$NEXTUPGRADESTEPVERSION"/" $CONFIGFILE
#	echo "">>"$CONFIGFILE"
#	echo "Upgrading config.ini from v$config_version to v$NEXTUPGRADESTEPVERSION"
#	config_version=$(awk -F "=" '/config_version=/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
#	echo "Upgraded config.ini to v$config_version"
#fi

### Crystools: Enforce deactivation of GPU Management. Problems detected, especially with TVAI.
COMFYUI_SETTINGS_FILE=`realpath "./user/default/comfy.settings.json"`
if [ -e "$COMFYUI_SETTINGS_FILE" ]; then
	PROHIBITED_SETTING_COUNT=`grep "\"Crystools.ShowGpu.*\": true" "$COMFYUI_SETTINGS_FILE" | wc -l`
	if [ $PROHIBITED_SETTING_COUNT -gt 0 ] ; then
		sed -i "/\"Crystools.ShowGpuTemperatureZero\":/s/: true/: false/" "$COMFYUI_SETTINGS_FILE"
		sed -i "/\"Crystools.ShowGpuVramZero\":/s/: true/: false/" "$COMFYUI_SETTINGS_FILE"
		sed -i "/\"Crystools.ShowGpuUsageZero\":/s/: true/: false/" "$COMFYUI_SETTINGS_FILE"
		echo -e $"\e[93mWarning:\e[0m ComfyUI settings changed ($PROHIBITED_SETTING_COUNT). Crystools.ShowGpu settings must be false.\n\e[95m*** Please restart ComfyUI ***\e[0m"
	fi
fi

TVAI_BIN_DIR=$(awk -F "=" '/TVAI_BIN_DIR=/ {print $2}' $CONFIGFILE) ; TVAI_BIN_DIR=${TVAI_BIN_DIR:-""}

### CHECK TOOLS ###
if ! command -v $FFMPEGPATHPREFIX"ffmpeg" >/dev/null 2>&1
then
	echo -e $"\e[91mError:\e[0m ffmpeg could not be found."
	CONFIGERROR="x"
fi

### CHECK MODELS ###
if [ ! -e models/upscale_models/$UPSCALEMODELx4 ]; then
	echo -e $"\e[91mError:\e[0m Upscale model $UPSCALEMODELx4 could not be found in models/upscale_models. Use Model Manager to install, or download file manually to models/upscale_models from https://github.com/xinntao/Real-ESRGAN/releases"
	CONFIGERROR="x"
fi
if [ ! -e models/upscale_models/$UPSCALEMODELx2 ]; then
	echo -e $"\e[91mError:\e[0m Upscale model $UPSCALEMODELx2 could not be found in models/upscale_models. Use Model Manager to install, or download file manually to models/upscale_models from https://github.com/xinntao/Real-ESRGAN/releases"
	CONFIGERROR="x"
fi
#SEARCHCOUNT_MODEL=`find $COMFYUIPATH/custom_nodes/comfyui_controlnet_aux/ckpts -name $DEPTH_MODEL_CKPT | wc -l`
#if [[ $SEARCHCOUNT_MODEL -eq 0 ]] ; then
	#if [ "$DEPTH_MODEL_CKPT" != "depth_anything_v2_vitl.pth" ] ; then
	#	echo -e $"\e[91mError:\e[0m Depth model $DEPTH_MODEL_CKPT could not be found in $COMFYUIPATH/custom_nodes/comfyui_controlnet_aux/ckpts"
	#	echo -e $"It must be installed manually. Spoiler: \e[36mhttps://www.reddit.com/r/comfyui/comments/1lchvqw/depth_anything_v2_giant/\e[0m"
	#	CONFIGERROR="x"
	#else
	#echo -e $"\e[94mInfo:\e[0m Depth model $DEPTH_MODEL_CKPT not yet downloaded by comfyui_controlnet_aux"
	#fi
#else
	#if [ "$DEPTH_MODEL_CKPT" == "depth_anything_v2_vitl.pth" ] ; then
	#	if [ -e custom_nodes/comfyui_controlnet_aux/ckpts/depth-anything/Depth-Anything-V2-Giant ] ; then
	#		[ $loglevel -ge 0 ] && echo -e $"\e[94mInfo:\e[0m default depth model used, but Depth-Anything-V2-Giant detected!"
	#		[ $loglevel -ge 0 ] && echo -e $"  Consider to update \e[92mDEPTH_MODEL_CKPT=depth_anything_v2_vitg.pth\e[0m in \e[36m$CONFIGFILE\e[0m"
	#	else
	#		[ $loglevel -ge 0 ] && echo -e $"\e[94mInfo:\e[0m default depth model used. To use Depth-Anything-V2-Giant install it manually."
	#		[ $loglevel -ge 0 ] && echo -e $"  Then update DEPTH_MODEL_CKPT in \e[36m$CONFIGFILE\e[0m"
	#		[ $loglevel -ge 0 ] && echo -e $"  Spoiler: \e[36mhttps://www.reddit.com/r/comfyui/comments/1lchvqw/depth_anything_v2_giant/\e[0m"
	#	fi
	#fi
#fi

# CHECK TOOLS
EXIFTOOLBINARY=$(awk -F "=" '/EXIFTOOLBINARY=/ {print $2}' $CONFIGFILE) ; EXIFTOOLBINARY=${EXIFTOOLBINARY:-""}
if [ ! -e "$EXIFTOOLBINARY" ]; then
	echo -e $"\e[94mInfo:\e[0m Tagging not available, Exif tool missing. Set path at \e[92mEXIFTOOLBINARY\e[0m in"
	echo -e $"\e[94m     \e[0m \e[36m$CONFIGFILE\e[0m"
	echo -e $"\e[94m     \e[0m You may download Exiftool by visiting \e[36mhttps://exiftool.org\e[0m"
	echo -e $"\e[94m     \e[0m The Exif tool binary must be renamed to exiftool.exe. Strip '(-k)' from name."
elif [[ "$EXIFTOOLBINARY" =~ "(-k)" ]]; then
	echo -e $"\e[91mError:\e[0m Exif tool binary must be renamed to exiftool.exe. Strip '(-k)' from name and update path at \e[92mEXIFTOOLBINARY\e[0m in"
	echo -e $"\e[91m      \e[0m \e[36m$CONFIGFILE\e[0m"
	exit 1
fi

if [ ! -z "$TVAI_BIN_DIR" ] && [ ! -d "$TVAI_BIN_DIR" ] ; then
	echo -e $"\e[93mWarning:\e[0m TVAI path set but now found. Please configure in $CONFIGFILE"":"
	echo -e $"\e[93mWarning:\e[0m TVAI_BIN_DIR=$TVAI_BIN_DIR"
fi


CONFIGPATH=user/default/comfyui_stereoscopic
CONFIGPATH=`realpath $CONFIGPATH`
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
cp input/vr/dubbing/DO_NOT_PLACE_HERE.TXT input/vr/tasks/DO_NOT_PLACE_HERE.TXT
mkdir -p input/vr/singleloop/error
#touch input/vr/singleloop/error/CONSIDER_REPAIRING

# Initialize input 'done' folders
mkdir -p input/vr
cd input/vr
if [ ! -e "$CONFIGPATH"/"rebuild_autoforward.sh" ] ; then
	for stagepath in scaling slides fullsbs singleloop slideshow concat dubbing/sfx watermark/encrypt watermark/decrypt caption interpolate ; do
		mkdir -p $stagepath/done
	done
	TASKDIR=`find tasks -maxdepth 1 -type d`
	for task in $TASKDIR; do
		task=${task#tasks/}
		if [ ! -z $task ] ; then
			mkdir -p tasks/$task/done
		fi
	done

	#touch fullsbs/done/.nocleanup slideshow/done/.nocleanup interpolate/done/.nocleanup dubbing/sfx/done/.nocleanup watermark/encrypt/done/.nocleanup watermark/decrypt/done/.nocleanup singleloop/done/.nocleanup slides/done/.nocleanup tasks/credit-vr-we-are/done/.nocleanup tasks/vlimit-720p/done/.nocleanup tasks/vlimit-1080p/done/.nocleanup tasks/split-1m/done/.nocleanup tasks/fps-limit-15/done/.nocleanup
	
fi
cd ../..

# Initialize folders
mkdir -p output/vr
cd output/vr
mkdir -p caption fullsbs scaling dubbing/sfx interpolate watermark/encrypt watermark/decrypt slides concat singleloop slideshow
cd ../..

# REBUILD FORWARD PIPELINE
if [ ! -e "$CONFIGPATH"/"autoforward.yaml" ] ; then
	if [ -e "$CONFIGPATH"/"default_autoforward.yaml" ] ; then
		cp "$CONFIGPATH"/"default_autoforward.yaml" "$CONFIGPATH"/"autoforward.yaml"	
	else
		cp ./custom_nodes/comfyui_stereoscopic/config/default_autoforward.yaml "$CONFIGPATH"/"autoforward.yaml"
	fi
fi
echo -e $"\e[2mRebuild forward rules with \e[36m$CONFIGPATH""/autoforward.yaml\e[0m"
# Clear forward definitions and rebuild.
#rm -f -- output/vr/*/forward.txt output/vr/*/*/forward.txt 2>/dev/null
#rm -f -- output/vr/*/forward.tmp output/vr/*/*/forward.tmp 2>/dev/null
echo -ne $"\e[91m"
"$PYTHON_BIN_PATH"python.exe ./custom_nodes/comfyui_stereoscopic/api/python/rebuild_autoforward.py 2>/dev/null
echo -e $"\e[0m"


[ $PIPELINE_AUTOFORWARD -ge 1 ] && echo -e $"Auto-Forwarding \e[32mactive\e[0m" || echo -e $"Auto-Forwarding \e[33mdeactivated\e[0m"
if [ ! -e "$CONFIGPATH"/uml/"autoforward.pu" ] || [ "$CONFIGPATH"/uml/"autoforward.pu" -ot "$CONFIGPATH"/"autoforward.yaml" ] ; then
	rm -f -- "$CONFIGPATH"/uml/*.* 2>/dev/null
	./custom_nodes/comfyui_stereoscopic/api/uml_build_definition.sh
fi
if [ ! -e "$CONFIGPATH"/uml/"autoforward.png" ] || [ ! -s "$CONFIGPATH"/uml/"autoforward.png" ] ; then
	# Requires to be online...
	./custom_nodes/comfyui_stereoscopic/api/uml_generate_image.sh
fi

# Cleanup
echo -e $"\e[2mCleaning up unprotected done folders\e[0m"
for stagepath in scaling slides fullsbs singleloop slideshow concat dubbing/sfx watermark/encrypt watermark/decrypt caption interpolate ; do
	if [ ! -f input/vr/$stagepath/done/.nocleanup ] ; then
		rm -f -- input/vr/$stagepath/done/* 2>/dev/null
	fi
done
TASKDIR=`find input/vr/tasks -maxdepth 1 -type d`
for task in $TASKDIR; do
	task=${task#input/vr/tasks/}
	if [ ! -z $task ] ; then
		if [ ! -f input/vr/tasks/$task/done/.nocleanup ] ; then
			rm -f -- input/vr/tasks/$task/done/* 2>/dev/null
		fi
	fi
done

# check if install enforces a test run and then wait for ComfyUI to be started.
if [ -e "custom_nodes/comfyui_stereoscopic/.test/.forced" ] ; then
  echo -e $"\e[94mWairing for ComfyUI to start tests.\e[0m"
  status="closed"
  while [ "$status" = "closed" ]; do
    status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
  done
  # now .install file should be present.
  rm -f "custom_nodes/comfyui_stereoscopic/.test/.forced"
fi

# CHECK FOR VERSION UPDATE FLAGGED BY __init__.py AND RUN TESTS
if [ -e "custom_nodes/comfyui_stereoscopic/.test/.install" ] ; then
	./custom_nodes/comfyui_stereoscopic/tests/run_tests.sh || exit 1
	if [ -e "custom_nodes/comfyui_stereoscopic/.test/.install" ] ; then
		echo -e $"\e[91mError:\e[0m Tests failed."
		touch "custom_nodes/comfyui_stereoscopic/.test/.signalfail"
		exit 1
	fi
fi

# Do initial auto-forward and cleanup
if [ $PIPELINE_AUTOFORWARD -ge 1 ] ; then
	echo -e $"\e[2mSearching for files left to forward and cleanup.\e[0m"
	for stagepath in scaling slides fullsbs singleloop slideshow concat dubbing/sfx watermark/encrypt watermark/decrypt caption interpolate ; do
		[ $loglevel -ge 1 ] && echo " - $stagepath"
		FILECOUNT=`find output/vr/$stagepath -maxdepth 1 -type f -name '*.*' | wc -l 2>/dev/null` 
		# forward.txt + one media
		if [ $FILECOUNT -gt 1 ] ; then
			./custom_nodes/comfyui_stereoscopic/api/forward.sh $stagepath || exit 1
		fi
		rm -rf -- output/vr/$stagepath/intermediate input/vr/$stagepath/intermediate 2>/dev/null
	done
	
	TASKDIR=`find output/vr/tasks -maxdepth 1 -type d`
	for task in $TASKDIR; do
		task=${task#output/vr/tasks/}
		if [ ! -z $task ] ; then
			[ $loglevel -ge 1 ] && echo " - tasks/$task"
			FILECOUNT=`find output/vr/$stagepath -maxdepth 1 -type f -name '*.*' | wc -l 2>/dev/null`  
			# forward.txt + one media
			if [ $FILECOUNT -gt 1 ] ; then
				./custom_nodes/comfyui_stereoscopic/api/forward.sh tasks/$task || exit 1
			fi
			rm -rf -- output/vr/$stagepath/intermediate input/vr/$stagepath/intermediate 2>/dev/null
		fi
	done
else
	echo -e $"\e[94mInfo:\e[0m Auto-Forward deactivated."
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

[ $loglevel -ge 0 ] && echo -e $"\e[2mFor processings read docs. \e[36mhttps://www.3d-gallery.org\e[0m"
[ $loglevel -ge 0 ] && echo -e $"\e[2mHint: You may use Control + Click on any links that appear.\e[0m"


### EXIT IF CHECK FAILED ###
if [[ ! -z $CONFIGERROR ]]; then
    echo "Configuration errors detected (see above) - stopping."
	exit 1
fi

exit 0
