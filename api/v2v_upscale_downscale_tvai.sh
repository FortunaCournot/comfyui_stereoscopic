#!/bin/sh
#
# v2v_upscale_downscale_tvai.sh || exit 1
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


if test $# -ne 1 -a $# -ne 2
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 input"
    echo "E.g.: $0 SmallIconicTown.mp4 override_active"
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

	DOWNSCALE=1.0
	INPUT="$1"
	shift
	override_active=$1
	

	TVAI_BIN_DIR=$(awk -F "=" '/TVAI_BIN_DIR/ {print $2}' $CONFIGFILE) ; TVAI_BIN_DIR=${TVAI_BIN_DIR:-""}
	TVAI_MODEL_DATA_DIR=$(awk -F "=" '/TVAI_MODEL_DATA_DIR/ {print $2}' $CONFIGFILE) ; TVAI_MODEL_DATA_DIR=${TVAI_MODEL_DATA_DIR:-""}
	TVAI_MODEL_DIR=$(awk -F "=" '/TVAI_MODEL_DIR/ {print $2}' $CONFIGFILE) ; TVAI_MODEL_DIR=${TVAI_MODEL_DIR:-""}
	TVAI_FILTER_STRING_UP4X=`grep TVAI_FILTER_STRING_UP4X= $CONFIGFILE | cut -d'=' -f2-`
	TVAI_FILTER_STRING_UP4X=${TVAI_FILTER_STRING_UP4X:-""}
	TVAI_MODEL4X=${TVAI_FILTER_STRING_UP4X#*"model="}
	TVAI_MODEL4X=${TVAI_MODEL4X%%:*}
	TVAI_FILTER_STRING_UP2X=`grep TVAI_FILTER_STRING_UP2X= $CONFIGFILE | cut -d'=' -f2-`
	TVAI_FILTER_STRING_UP2X=${TVAI_FILTER_STRING_UP2X:-""}
	TVAI_MODEL2X=${TVAI_FILTER_STRING_UP2X#*"model="}
	TVAI_MODEL2X=${TVAI_MODEL2X%%:*}

	if [ -e "$TVAI_BIN_DIR" ] && [ -e "$TVAI_MODEL_DATA_DIR" ] && [ -e "$TVAI_MODEL_DIR" ] && [ -e "$TVAI_MODEL_DIR"/$TVAI_MODEL4X".json" ] && [ -e "$TVAI_MODEL_DIR"/$TVAI_MODEL2X".json" ] ; then
		export TVAI_MODEL_DATA_DIR TVAI_MODEL_DIR
	else
		echo -e $"\e[91mError:\e[0m TVAI settings wrong. Please configure at $CONFIGFILE"":"
		[ ! -e "$TVAI_BIN_DIR" ] && echo -e $"\e[91mError:\e[0m TVAI_BIN_DIR=$TVAI_BIN_DIR"
		[ ! -e "$TVAI_MODEL_DATA_DIR" ] && echo -e $"\e[91mError:\e[0m TVAI_MODEL_DATA_DIR=$TVAI_MODEL_DATA_DIR"
		[ ! -e "$TVAI_MODEL_DIR" ] && echo -e $"\e[91mError:\e[0m TVAI_MODEL_DIR=$TVAI_MODEL_DIR"
		[ ! -e "$TVAI_MODEL_DIR"/$TVAI_MODEL2X".json" ] && echo -e $"\e[91mError:\e[0m TVAI_FILTER_STRING_UP2X=$TVAI_FILTER_STRING_UP2X"
		[ ! -e "$TVAI_MODEL_DIR"/$TVAI_MODEL2X".json" ] && echo -e $"\e[91mE     \e[0m ""$TVAI_MODEL_DIR"/$TVAI_MODEL2X".json not found in $TVAI_MODEL_DATA_DIR"
		[ ! -e "$TVAI_MODEL_DIR"/$TVAI_MODEL4X".json" ] && echo -e $"\e[91mError:\e[0m TVAI_FILTER_STRING_UP4X=$TVAI_FILTER_STRING_UP4X"
		[ ! -e "$TVAI_MODEL_DIR"/$TVAI_MODEL4X".json" ] && echo -e $"\e[91mE     \e[0m ""$TVAI_MODEL_DIR"/$TVAI_MODEL4X".json not found in $TVAI_MODEL_DATA_DIR"
		exit 1
	fi
	
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
		exit 0
	fi
	PIXEL=$(( $RESW * $RESH ))
	
	LIMIT4X=$(awk -F "=" '/LIMIT4X_NORMAL/ {print $2}' $CONFIGFILE) ; LIMIT4X=${LIMIT4X:-"518400"}
	LIMIT2X=$(awk -F "=" '/LIMIT2X_NORMAL/ {print $2}' $CONFIGFILE) ; LIMIT2X=${LIMIT2X:-"2073600"}
	if [ $override_active -gt 0 ]; then
		[ $loglevel -ge 0 ] && echo "override active"
		LIMIT4X=$(awk -F "=" '/LIMIT4X_OVERRIDE/ {print $2}' $CONFIGFILE) ; LIMIT4X_OVERRIDE=${LIMIT4X_OVERRIDE:-"1036800"}
		duration=`"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=nw=1:nk=1 $INPUT`
		duration=${duration%.*}
		if test $duration -ge 60 ; then
			LIMIT2X=$(awk -F "=" '/LIMIT2X_OVERRIDE_LONG/ {print $2}' $CONFIGFILE) ; LIMIT2X_OVERRIDE_LONG=${LIMIT2X_OVERRIDE_LONG:-"4147200"}
			[ $loglevel -ge 0 ] && echo "long video detected."
		fi
	fi


	if [ $PIXEL -lt $LIMIT2X ]; then
		if [ $PIXEL -lt $LIMIT4X ]; then
			TARGETPREFIX="$TARGETPREFIX""_x4"
			UPSCALEFACTOR=4
			TVAI_FILTER_STRING="$TVAI_FILTER_STRING_UP4X"
			[ $loglevel -ge 1 ] && echo "using $UPSCALEFACTOR""x"
		else
			TARGETPREFIX="$TARGETPREFIX""_x2"
			UPSCALEFACTOR=2
			TVAI_FILTER_STRING="$TVAI_FILTER_STRING_UP2X"
			[ $loglevel -ge 1 ] && echo "using $UPSCALEFACTOR""x"
		fi
	else
		[ $loglevel -ge 0 ] && echo "Large video ($PIXEL > $LIMIT2X): Forwardung input to output folder"
		mv -vf -- "$INPUT" $FINALTARGETFOLDER
		exit 1
	fi
	
	
	"$TVAI_BIN_DIR"/ffmpeg.exe -hide_banner -stats  -nostdin -y -strict 2 -hwaccel auto -i "$INPUT" -c:v libvpx-vp9 -g 300 -crf 19 -b:v 2000k -c:a aac -pix_fmt yuv420p -movflags frag_keyframe+empty_moov -filter_complex "$TVAI_FILTER_STRING" "$TARGETPREFIX"".mkv"
	if [ -e "$TARGETPREFIX"".mkv" ] ; then
		"$FFMPEGPATHPREFIX"ffmpeg -hide_banner -v quiet -stats -y -i "$TARGETPREFIX"".mkv" -c:v libx264 -crf 19 -c:a aac -pix_fmt yuv420p -movflags frag_keyframe+empty_moov "$TARGETPREFIX"".mp4"
		rm -f "$TARGETPREFIX"".mkv"
		mv "$TARGETPREFIX"".mp4" $FINALTARGETFOLDER
		mkdir -p input/vr/scaling/done
		mv -f -- "$INPUT" input/vr/scaling/done
		[ $loglevel -ge 0 ] && echo "done."
	else
		echo -e $"\e[91mError:\e[0m TVAI generation failed. Please check TVAI_FILTER_STRING in $CONFIGFILE"
		mkdir -p input/vr/scaling/error
		mv -fv -- "$INPUT" input/vr/scaling/error
	fi
fi
exit 0

