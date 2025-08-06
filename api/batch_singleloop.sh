#!/bin/sh
#
# v2v_singleloop.sh
#
# Reverse a video (input) and concat them. For multiple input videos (I2V: all must have same start frame, same resolution, etc. ) do same for each and concat all with silence audio.
#
# Copyright (c) 2025 FortunaCournot. MIT License.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable. ComfyUI server is not used.
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# set FFMPEGPATHPREFIX if ffmpeg binary is not in your enviroment path
# relative to COMFYUIPATH:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/v2v_singleloop.sh 

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

	mkdir -p output/vr/singleloop/intermediate
	mkdir -p input/vr/singleloop/done
	
	COUNT=`find input/vr/singleloop -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' | wc -l`
	declare -i INDEX=0
	if [[ $COUNT -gt 0 ]] ; then
		VIDFILES=`find input/vr/singleloop -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm'`
		for nextinputfile in $VIDFILES ; do
			INDEX+=1
			echo "$INDEX/$COUNT" >input/vr/singleloop/BATCHPROGRESS.TXT
			newfn=${nextinputfile//[^[:alnum:]]/_}
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
				INTERMEDIATEFILE=`realpath "output/vr/singleloop/intermediate/$TARGETPREFIX""_loop.mp4"`
				/bin/bash $SCRIPTPATH  $INTERMEDIATEFILE `realpath "$newfn"`
				
				if [ -e $INTERMEDIATEFILE ]
				then
					mv -- $INTERMEDIATEFILE output/vr/singleloop/$TARGETPREFIX"_loop.mp4"
					mv -- $newfn input/vr/singleloop/done
				else
					echo -e $"\e[91mError:\e[0m creating loop failed. Missing file: output/vr/singleloop/intermediate/$TARGETPREFIX""_loop.mp4"
					mkdir -p input/vr/singleloop/error
					mv -- $newfn input/vr/singleloop/error
				fi
			else
				echo -e $"\e[91mError:\e[0m prompting failed. Missing file: $newfn"
			fi			
			
		done
	fi
	rm -f input/vr/singleloop/BATCHPROGRESS.TXT
	echo "Batch done.                             "
fi
