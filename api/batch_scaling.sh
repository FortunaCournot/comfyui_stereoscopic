#!/bin/sh
# Upscales videos in batch from all base videos placed in ComfyUI/input/vr/scaling (input)
# 
# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).


# relative or abolute path of ComfyUI folder in your ComfyUI_windows_portable
# Default: Executed in ComfyUI folder
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# relative to COMFYUIPATH:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/v2v_upscale_downscale.sh 
SCRIPTPATH2=./custom_nodes/comfyui_stereoscopic/api/i2i_upscale_downscale.sh 

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

FREESPACE=$(df -khBG . | tail -n1 | awk '{print $4}')
FREESPACE=${FREESPACE%G}
MINSPACE=10
status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
if [ "$status" = "closed" ]; then
    echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
elif [[ $FREESPACE -lt $MINSPACE ]] ; then
	echo -e $"\e[91mError:\e[0m Less than $MINSPACE""G left on device: $FREESPACE""G"
elif test $# -ne 0 -a $# -ne 1; then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 [OVERRIDESUBPATH]"
    echo "E.g.: $0 /override"
else
	if test $# -eq 1; then
		OVERRIDESUBPATH="$1"
		shift
		
		mv -fv "input/vr/scaling""$OVERRIDESUBPATH"/*.* input/vr/scaling
	fi
	
	COUNT=`find input/vr/scaling -maxdepth 1 -type f -name '*.mp4' | wc -l`
	[ $loglevel -ge 1 ] && echo "Video Count: $COUNT"
	declare -i INDEX=0
	if [[ $COUNT -gt 0 ]] ; then
		for nextinputfile in input/vr/scaling/*.mp4 ; do
			INDEX+=1
			echo "$INDEX/$COUNT" >input/vr/scaling/BATCHPROGRESS.TXT
			newfn=${nextinputfile//[^[:alnum:.]]/}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			mv "$nextinputfile" $newfn 
			
			if [ -e "$newfn" ]
			then
				duration=-1
				override_active=1
				if [ -z "$OVERRIDESUBPATH" ]; then
					duration=`"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=nw=1:nk=1 $newfn`
					duration=${duration%.*}
					override_active=0
				fi
				if test $duration -ge 60
				then
					echo -e $"\e[93mWarning:\e[0m long video (>60s) detected; call $SCRIPTPATH directly or move it to input/vr/scaling$OVERRIDESUBPATH. Skipping $newfn"
					mkdir -p input/vr/scaling/stopped
					mv -fv "$newfn" input/vr/scaling/stopped
					sleep 10	# file will stay - this cause daemon to loop foreve - ensure user can read message
				else
					/bin/bash $SCRIPTPATH "$newfn" $override_active 
					
					status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
					if [ "$status" = "closed" ]; then
						echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
						exit
					fi
				fi
			else
				echo -e $"\e[91mError:\e[0m prompting failed. Missing file: $newfn"
			fi			
			
		done
	fi
	rm -f input/vr/scaling/BATCHPROGRESS.TXT
	
	IMGFILES=`find input/vr/scaling -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG'`
	COUNT=`find input/vr/scaling -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
	declare -i INDEX=0
	[ $loglevel -ge 1 ] && echo "Image Count: $COUNT"
	if [[ $COUNT -gt 0 ]] ; then
		for nextinputfile in $IMGFILES ; do
			INDEX+=1
			echo "$INDEX/$COUNT" >input/vr/scaling/BATCHPROGRESS.TXT
			newfn=${nextinputfile//[^[:alnum:.]]/}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			mv "$nextinputfile" $newfn 
			
			if [[ "$newfn" == *_x?* ]]; then
				echo "Skipping $newfn (already scaled)"
				mkdir -p output/vr/scaling
				mv -fv $newfn output/vr/scaling
			elif [ -e "$newfn" ]
			then
				duration=-1
				override_active=1
				if [ -z "$OVERRIDESUBPATH" ]; then
					override_active=0
				fi

				/bin/bash $SCRIPTPATH2 "$newfn" $override_active 
				
				status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
				if [ "$status" = "closed" ]; then
					echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
					exit
				fi

			else
				echo -e $"\e[91mError:\e[0m prompting failed. Missing file: $newfn"
			fi			
			
		done
	fi
	rm -f input/vr/scaling/BATCHPROGRESS.TXT
	
	[ $loglevel -ge 1 ] && echo "Batch done."

fi

