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

	mkdir -p output/vr/singleloop/intermediate
	mkdir -p input/vr/singleloop/done
	mkdir -p input/vr/starloop
	
	IMGFILES=`find input/vr/singleloop -maxdepth 1 -type f -name '*.mp4'`
	COUNT=`find input/vr/singleloop -maxdepth 1 -type f -name '*.mp4' | wc -l`
	INDEX=0
	if [[ $COUNT -gt 0 ]] ; then
	
		for nextinputfile in input/vr/singleloop/*.mp4 ; do
			INDEX+=1
			echo "$INDEX/$COUNT">input/vr/fullsbs/BATCHPROGRESS.TXT
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
				TARGETPREFIX=${TARGETPREFIX//"_dub"/}
				/bin/bash $SCRIPTPATH `realpath "output/vr/singleloop/intermediate/$TARGETPREFIX""_loop.mp4"` `realpath "$newfn"`
				if [ -e output/vr/singleloop/intermediate/$TARGETPREFIX"_loop.mp4" ]
				then
					mv output/vr/singleloop/intermediate/$TARGETPREFIX"_loop.mp4" output/vr/singleloop/$TARGETPREFIX"_loop.mp4"
					mv $newfn input/vr/singleloop/done
				else
					echo "Error: creating loop failed. Missing file: output/vr/singleloop/intermediate/$TARGETPREFIX""_loop.mp4"
					mkdir -p input/vr/starloop/error
					mv $newfn input/vr/singleloop/error
				fi
			else
				echo "Error: prompting failed. Missing file: $newfn"
			fi			
			
		done
		rm  -f input/vr/fullsbs/BATCHPROGRESS.TXT 
	fi
	echo "Batch done.                             "
fi
