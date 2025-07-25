#!/bin/sh
#
# v2v_singleloop.sh
#
# Reverse a video (input) and concat them. For multiple input videos (I2V: all must have same start frame, same resolution, etc. ) do same for each and concat all with silence audio.
#
# Copyright (c) 2025 FortunaCournot. MIT License.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable. ComfyUI server is not used.
COMFYUIPATH=.
# set FFMPEGPATH if ffmpeg binary is not in your enviroment path
FFMPEGPATH=
# relative to COMFYUIPATH:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/v2v_starloop.sh 

FREESPACE=$(df -khBG . | tail -n1 | awk '{print $4}')
FREESPACE=${FREESPACE%G}
MINSPACE=10
status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
if test $# -gt 0
then
    echo "Usage: $0 "
    echo "E.g.: $0"
elif [[ $FREESPACE -lt $MINSPACE ]] ; then
	echo -e $"\e[91mError:\e[0m Less than $MINSPACE""G left on device: $FREESPACE""G"
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

	mkdir -p output/vr/starloop/intermediate
	mkdir -p input/vr/starloop/done
	
	IMGFILES=`find input/vr/starloop -maxdepth 1 -type f -name '*.mp4'`
	COUNT=`find input/vr/starloop -maxdepth 1 -type f -name '*.mp4' | wc -l`
	INDEX=0
	if [[ $COUNT -gt 0 ]] ; then
	
		echo "" >output/vr/starloop/intermediate/mylist.txt
		for nextinputfile in input/vr/starloop/*.mp4 ; do
			INDEX+=1
			newfn=part_$INDEX.mp4
			cp "$nextinputfile" output/vr/starloop/intermediate/$newfn 
			
			if [ -e "output/vr/starloop/intermediate/$newfn" ]
			then
				echo "file $newfn" >>output/vr/starloop/intermediate/mylist.txt
			else
				echo -e $"\e[91mError:\e[0m prompting failed. Missing file: output/vr/starloop/intermediate/$newfn"
				exit
			fi						
		done
		
		NOW=$( date '+%F_%H%M' )	
		TARGET=output/vr/starloop/starloop-$NOW"_SBS_LR".mp4		# assume it is SBS
		
		cd output/vr/starloop/intermediate
		echo -ne "Concat ($COUNT)...                             \r"
		nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i mylist.txt -c copy result.mp4
		if [ ! -e "result.mp4" ]; then echo -e $"\e[91mError:\e[0m failed to create result.mp4" && exit ; fi
		
		
		cd ../../../..
		mv -f output/vr/starloop/intermediate/result.mp4 "$TARGET"
		mv input/vr/starloop/*.mp4 input/vr/starloop/done
		
		if [ -e "$TARGET" ]; then
			rm -f output/vr/starloop/intermediate/*
		else
			echo -e $"\e[91mError:\e[0m Failed to create target file $TARGET"
		fi
		echo "All done.                             "
	
	fi
	echo "Batch ($COUNT) done.                             "
fi
