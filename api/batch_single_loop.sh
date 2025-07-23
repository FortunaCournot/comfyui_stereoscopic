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
# relative to COMFYUIPATH:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/v2v_starloop.sh 

FREESPACE=$(df -khBG . | tail -n1 | awk '{print $4}')
FREESPACE=${FREESPACE%G}
MINSPACE=10
status=`true &>/dev/null </dev/tcp/127.0.0.1/8188 && echo open || echo closed`
if test $# -gt 0
then
    echo "Usage: $0 "
    echo "E.g.: $0"
elif [[ $FREESPACE -lt $MINSPACE ]] ; then
	echo "Error: Less than $MINSPACE""G left on device: $FREESPACE""G"
else
	cd $COMFYUIPATH

	mkdir -p output/singleloop/intermediate
	mkdir -p input/singleloop_in/done
	mkdir -p input/starloop_in
	
	IMGFILES=`find input/singleloop_in -maxdepth 1 -type f -name '*.mp4'`
	COUNT=`find input/singleloop_in -maxdepth 1 -type f -name '*.mp4' | wc -l`
	INDEX=0
	if [[ $COUNT -gt 0 ]] ; then
	
		for nextinputfile in input/singleloop_in/*.mp4 ; do
			INDEX+=1
			echo "$INDEX/$COUNT">input/sbs_in/BATCHPROGRESS.TXT
			newfn=${nextinputfile//[^[:alnum:.]]/}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			newfn=$newfn
			mv "$nextinputfile" $newfn 
			
			if [ -e "$newfn" ]
			then
				TARGETPREFIX=${newfn##*/}
				TARGETPREFIX=${TARGETPREFIX%.mp4}
				/bin/bash $SCRIPTPATH `realpath "output/singleloop/intermediate/$TARGETPREFIX""_L.mp4"` `realpath "$newfn"`
				if [ -e output/singleloop/intermediate/$TARGETPREFIX"_loop.mp4" ]
				then
					mv output/singleloop/intermediate/$TARGETPREFIX"_loop.mp4" output/singleloop/$TARGETPREFIX"_loop.mp4"
					mv $newfn input/singleloop_in/done
				else
					echo "Error: creating loop failed. Missing file: output/singleloop/intermediate/$TARGETPREFIX""_L.mp4"
				fi
			else
				echo "Error: prompting failed. Missing file: $newfn"
			fi			
			
		done
		rm  -f input/sbs_in/BATCHPROGRESS.TXT 
	fi
	echo "Batch done.                             "
fi
