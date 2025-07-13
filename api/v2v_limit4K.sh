#!/bin/sh
#
# v2v_limit4K.sh
#
# Downscales a video (input) to 4K resolution (3840 width). the targetvideo is same path adding _4K to filename.
#
# Copyright (c) 2025 FortunaCournot. MIT License.

# ComfyUI is not used.

# set FFMPEGPATH if ffmpeg binary is not in your enviroment path
FFMPEGPATH=
# either start this script in ComfyUI folder or enter absolute path of ComfyUI folder in your ComfyUI_windows_portable here

if test $# -ne 1
then
    echo "Usage: $0 input"
    echo "E.g.: $0 SmallIconicTown_SBS_LR.mp4"
else
	cd $COMFYUIPATH

	INPUT="$1"
	shift
	
	TARGETPREFIX=${INPUT##*/}
	TARGETPREFIX=${TARGETPREFIX%.mp4}_4K
	INPUT=`realpath "$INPUT"`
	INPUTPATH=`dirname $INPUT`
	if test `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $INPUT` -gt 3840
	then 
		echo "Downscaling to $INPUTPATH/$TARGETPREFIX"".mp4"
		nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i "$INPUT" -filter:v scale=3840:-1 -c:a copy "$INPUTPATH/$TARGETPREFIX"".mp4"
	else
		echo "Skipping downscaling of video $INPUT: not above 4K"
	fi
fi

