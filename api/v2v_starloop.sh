#!/bin/sh
#
# v2v_starloop.sh
#
# Reverse a video (input) and concat them. For multiple input videos (I2V: all must have same start frame, same resolution, etc. ) do same for each and concat all with silence audio. All input video parameter must be absolute path.
#
# Copyright (c) 2025 FortunaCournot. MIT License.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable. ComfyUI server is not used.
COMFYUIPATH=.
# set FFMPEGPATH if ffmpeg binary is not in your enviroment path
FFMPEGPATH=
# either start this script in ComfyUI folder or enter absolute path of ComfyUI folder in your ComfyUI_windows_portable here

if test $# -lt 2
then
    echo "Usage: $0 output input..."
    echo "E.g.: $0  output/starloop/test_SBS_LR.mp4 video1.mp4 video2.mp4 video3.mp4"
else
	cd $COMFYUIPATH

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

export CONFIGFILE
if [ -e $CONFIGFILE ] ; then
    config_version=$(awk -F "=" '/config_version/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
	COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
	COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
	export COMFYUIHOST COMFYUIPORT
else
    touch "$CONFIGFILE"
    echo "config_version=1">>"$CONFIGFILE"
fi

	TARGET="$1"
	shift
	
	mkdir -p output/starloop/intermediate
	rm -f output/starloop/intermediate/* 2>/dev/null
	
	declare -i i=0
	echo "" >output/starloop/intermediate/mylist.txt
	for FORWARD in "$@"
	do
		if [ ! -e "$FORWARD" ]; then echo "Error: failed to load $FORWARD" && exit ; fi
		FPATH=`realpath "$FORWARD"`
		cd output/starloop/intermediate
		i+=1
		echo -ne "Reversing #$i: ...                \r"
		LOOPSEGMENT="part_$i.mp4"
		# reverse audio does not sound well. it needs redubbing. [0:a]areverse[a];  -map "[a]" 
		nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i "$FPATH" -filter_complex "[0:v]reverse,fifo[rv];[0:v][rv]concat=n=2:v=1[v]" -map "[v]" "$LOOPSEGMENT"
		echo "file part_$i.mp4" >>mylist.txt
		cd ../../..
	done

	cd output/starloop/intermediate
	echo -ne "Concat...                             \r"
	nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i mylist.txt -c copy result.mp4
	if [ ! -e "result.mp4" ]; then echo "Error: failed to create result.mp4" && exit ; fi
	
	#echo -ne "Add audio channel...                             \r"
	#nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y  -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 -i result.mp4 -c:v copy -c:a aac -shortest result_sil.mp4  
	#if [ ! -e "result.mp4" ]; then echo "Error: failed to create result_sil.mp4" && exit ; fi
	cd ../../..
	mv -f output/starloop/intermediate/result.mp4 "$TARGET"

	
	if [ -e "$TARGET" ]; then
		rm -f output/starloop/intermediate/*
	else
		echo "Error: Failed to create target file $TARGET"
	fi
	echo "All done.                             "
fi
