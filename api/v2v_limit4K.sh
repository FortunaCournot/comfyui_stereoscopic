#!/bin/sh
#
# v2v_limit4K.sh
#
# Downscales a video (input) to 4K resolution (3840 width). the targetvideo is same path adding _4K to filename.
#
# Copyright (c) 2025 FortunaCournot. MIT License.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable. ComfyUI server is not used.
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# either start this script in ComfyUI folder or enter absolute path of ComfyUI folder in your ComfyUI_windows_portable here

if test $# -ne 1
then
    echo "Usage: $0 input"
    echo "E.g.: $0 SmallIconicTown_SBS_LR.mp4"
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

	# set FFMPEGPATHPREFIX if ffmpeg binary is not in your enviroment path
	FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}

	
	INPUT="$1"
	shift
	
	TARGETPREFIX=${INPUT##*/}
	TARGETPREFIX=${TARGETPREFIX%.mp4}_4K
	INPUT=`realpath "$INPUT"`
	INPUTPATH=`dirname $INPUT`
	if test `"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $INPUT` -gt 3840
	then 
		echo "H-Downscaling to $INPUTPATH/$TARGETPREFIX"".mp4"
		nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i "$INPUT" -filter:v scale=3840:-2 -c:a copy "$INPUTPATH/$TARGETPREFIX"".mp4"
	elif test `"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $INPUT` -gt 3840
	then 
		echo "V-Downscaling to $INPUTPATH/$TARGETPREFIX"".mp4"
		nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i "$INPUT" -filter:v scale=-2:3840 -c:a copy "$INPUTPATH/$TARGETPREFIX"".mp4"
	else
		echo "Skipping downscaling of video $INPUT: not above 4K"
	fi
fi

