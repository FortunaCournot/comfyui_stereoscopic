#!/bin/sh
#
# v2v_upscale_downscale_tvai.sh
#
# Upscales a base video (input) with Topaz Video AI and places result under ComfyUI/output/vr/scaling folder.
#
# Copyright (c) 2025 FortunaCournot. MIT License.


# Prerequisite: Topaz Video AI pathes must be configured and login active.
# Prerequisite: Git Bash installed. Call this script in Git Bash

# either start this script in ComfyUI folder or enter absolute path of ComfyUI folder in your ComfyUI_windows_portable here
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# API relative to COMFYUIPATH, or absolute path:
SCRIPTPATH=


if test $# -ne 1 
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 input [upscalefactor]"
    echo "E.g.: $0 SmallIconicTown.mp4 override_active [upscalefactor]"
else
	cd $COMFYUIPATH

	CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

	export CONFIGFILE
	if [ -e $CONFIGFILE ] ; then
		loglevel=$(awk -F "=" '/loglevel/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
		[ $loglevel -ge 2 ] && set -x
		config_version=$(awk -F "=" '/config_version/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
		COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
		COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
		export COMFYUIHOST COMFYUIPORT
	else
		touch "$CONFIGFILE"
		echo "config_version=1">>"$CONFIGFILE"
	fi

	EXIFTOOLBINARY=$(awk -F "=" '/EXIFTOOLBINARY/ {print $2}' $CONFIGFILE) ; EXIFTOOLBINARY=${EXIFTOOLBINARY:-""}

	# set FFMPEGPATHPREFIX if ffmpeg binary is not in your enviroment path
	FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}

	# Use Systempath for python by default, but set it explictly for comfyui portable.
	PYTHON_BIN_PATH=
	if [ -d "../python_embeded" ]; then
	  PYTHON_BIN_PATH=../python_embeded/
	fi

	TVAI_BIN_DIR=$(awk -F "=" '/TVAI_BIN_DIR/ {print $2}' $CONFIGFILE) ; TVAI_BIN_DIR=${TVAI_BIN_DIR:-""}
	TVAI_MODEL_DATA_DIR=$(awk -F "=" '/TVAI_MODEL_DATA_DIR/ {print $2}' $CONFIGFILE) ; TVAI_MODEL_DATA_DIR=${TVAI_MODEL_DATA_DIR:-""}
	TVAI_MODEL_DIR=$(awk -F "=" '/TVAI_MODEL_DIR/ {print $2}' $CONFIGFILE) ; TVAI_MODEL_DIR=${TVAI_MODEL_DIR:-""}
	TVAI_FILTER_STRING=`grep TVAI_FILTER_STRING $CONFIGFILE | cut -d'=' -f2-`
	TVAI_FILTER_STRING=${TVAI_FILTER_STRING:-""}
	TVAI_MODEL=${TVAI_FILTER_STRING#*"model="}
	TVAI_MODEL=${TVAI_MODEL%%:*}

	if [ -e "$TVAI_BIN_DIR" ] && [ -e "$TVAI_MODEL_DATA_DIR" ] && [ -e "$TVAI_MODEL_DIR" ] && [ -e "$TVAI_MODEL_DIR"/$TVAI_MODEL".json" ] ; then
		export TVAI_MODEL_DATA_DIR TVAI_MODEL_DIR
	else
		echo -e $"\e[91mError:\e[0m TVAI settings wrong. Please configure at $CONFIGFILE"":"
		[ ! -e "$TVAI_BIN_DIR" ] && echo -e $"\e[91mError:\e[0m TVAI_BIN_DIR=$TVAI_BIN_DIR"
		[ ! -e "$TVAI_MODEL_DATA_DIR" ] && echo -e $"\e[91mError:\e[0m TVAI_MODEL_DATA_DIR=$TVAI_MODEL_DATA_DIR"
		[ ! -e "$TVAI_MODEL_DIR" ] && echo -e $"\e[91mError:\e[0m TVAI_MODEL_DIR=$TVAI_MODEL_DIR"
		[ ! -e "$TVAI_MODEL_DIR"/$TVAI_MODEL".json" ] && echo -e $"\e[91mError:\e[0m TVAI_FILTER_STRING=$TVAI_FILTER_STRING"
		[ ! -e "$TVAI_MODEL_DIR"/$TVAI_MODEL".json" ] && echo -e $"\e[91mE     \e[0m ""$TVAI_MODEL_DIR"/$TVAI_MODEL".json not found in $TVAI_MODEL_DATA_DIR"
		exit
	fi
	
	#DOWNSCALE=1.0
	INPUT="$1"
	shift
	
	#UPSCALEFACTOR=0
	
	PROGRESS=" "
	if [ -e input/vr/scaling/BATCHPROGRESS.TXT ]
	then
		PROGRESS=`cat input/vr/scaling/BATCHPROGRESS.TXT`" "
	fi
	regex="[^/]*$"
	[ $loglevel -ge 0 ] && echo "========== $PROGRESS""rescale (tvai) "`echo $INPUT | grep -oP "$regex"`" =========="
	
	TARGETPREFIX=${INPUT##*/}
	INPUT=`realpath "$INPUT"`
	TARGETPREFIX_UPSCALE=${TARGETPREFIX%.*}
	TARGETPREFIX=output/vr/scaling/intermediate/$TARGETPREFIX_UPSCALE
	FINALTARGETFOLDER=`realpath "output/vr/scaling"`
	
	VIDEO_PIXFMT=$(awk -F "=" '/VIDEO_PIXFMT/ {print $2}' $CONFIGFILE) ; VIDEO_PIXFMT=${VIDEO_PIXFMT:-"yuv420p"}
	VIDEO_CRF=$(awk -F "=" '/VIDEO_CRF/ {print $2}' $CONFIGFILE) ; VIDEO_CRF=${VIDEO_CRF:-"17"}
	
	RESW=`"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $INPUT`
	RESH=`"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $INPUT`
	if [ `echo $RESW | wc -l` -ne 1 ] || [ `echo $RESH | wc -l` -ne 1 ] ; then
		echo -e $"\e[91mError:\e[0m Can't process video. please resample ${INPUT##*/} from input/vr/scaling/error"
		mkdir -p input/vr/scaling/error
		mv -f --  $INPUT input/vr/scaling/error
		exit
	fi
	
	# -preset high 
	#"$TVAI_BIN_DIR"/ffmpeg.exe -v 0 -encoders | findstr "nvenc"
	# -profile main
	# -preset medium -b_ref_mode 0 -crf 19 
	"$TVAI_BIN_DIR"/ffmpeg.exe -hide_banner -stats  -nostdin -y -strict 2 -hwaccel auto -i "$INPUT" -c:v wmv2  -g 30 -c:a aac -pix_fmt yuv420p -movflags frag_keyframe+empty_moov -filter_complex "$TVAI_FILTER_STRING" "$TARGETPREFIX""_tvai.wmv"
	"$FFMPEGPATHPREFIX"ffmpeg -hide_banner -v quiet -stats -y -i "$TARGETPREFIX""_tvai.wmv" -c:v libx265 -crf 19 -g 30 -c:a aac -pix_fmt yuv420p -movflags frag_keyframe+empty_moov "$TARGETPREFIX"".mp4"
	rm -f "$TARGETPREFIX""_tvai.wmv"
	mv "$TARGETPREFIX"".mp4" $FINALTARGETFOLDER
	[ $loglevel -ge 0 ] && echo "done."
fi

