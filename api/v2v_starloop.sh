#!/bin/sh
#
# v2v_starloop.sh
#
# Reverse a video (input) and concat them. For multiple input videos (I2V: all must have same start frame, same resolution, etc. ) do same for each and concat all with silence audio.
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

	TARGET="$1"
	shift
	touch "$TARGET"
	TARGET=`realpath "$TARGET"`
	
	mkdir -p output/starloop/intermediate
	rm -f output/starloop/intermediate/* 2>/dev/null
	
	declare -i i=0
	cd output/starloop/intermediate
	echo "" >mylist.txt
	for FORWARD in "$@"
	do
		i+=1
		echo -ne "Reversing #$i: ...                \r"
		LOOPSEGMENT="part_$i.mp4"
		nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i `realpath "$FORWARD"` -filter_complex "[0:v]reverse,fifo[r];[0:v][r] concat=n=2:v=1 [v]" -map "[v]" "$LOOPSEGMENT"
		echo "file part_$i.mp4" >>mylist.txt
	done

	echo -ne "Concat...                             \r"
	nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i mylist.txt -c copy result.mkv
	
	echo -ne "Add audio channel...                             \r"
	nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y  -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 -i result.mkv -f ffmetadata metadata.txt -c:v copy -c:a aac -shortest "$TARGET"

	cd ../../..
	
	if [ -e "$TARGET" ]; then
		rm -f output/starloop/intermediate/*
	fi
	echo "All done.                             "
fi
