#!/bin/sh
# Upscales videos in batch from all base videos placed in ComfyUI/input/vr/scaling (input)
# 
# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).

# relative or abolute path of ComfyUI folder in your ComfyUI_windows_portable
# Default: Executed in ComfyUI folder
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# relative to COMFYUIPATH:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/v2v_upscale_downscale.sh 
SCRIPTPATH2=./custom_nodes/comfyui_stereoscopic/api/i2i_upscale_downscale.sh 
SCRIPTPATH_TVAI=./custom_nodes/comfyui_stereoscopic/api/v2v_upscale_downscale_tvai.sh 

cd $COMFYUIPATH

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

export CONFIGFILE
if [ -e $CONFIGFILE ] ; then
	loglevel=$(awk -F "=" '/loglevel=/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
	[ $loglevel -ge 2 ] && set -x
    config_version=$(awk -F "=" '/config_version=/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
	COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST=/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
	COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT=/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
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
	mkdir -p output/vr/scaling/intermediate

	if test $# -eq 1; then
		OVERRIDESUBPATH="$1"
		shift
		
		mv -fv "input/vr/scaling""$OVERRIDESUBPATH"/*.* input/vr/scaling
	fi
	
	TVAI_BIN_DIR=$(awk -F "=" '/TVAI_BIN_DIR=/ {print $2}' $CONFIGFILE | head -n 1) ; TVAI_BIN_DIR=${TVAI_BIN_DIR:-""}
	
	#for file in input/vr/scaling/*' '*
	#do
	#	if [ -e "${file// /_}" ]
	#	then
	#		echo -e $"\e[91mError:\e[0m skipping $file as the renamed version already exists"
	#		mkdir -p input/vr/scaling/error
	#		mv -- "$file" input/vr/scaling/error
	#		continue
	#	fi
	#
	#	mv -- "$file" "${file// /_}"
	#done
	
	for f in input/vr/scaling/*\ *; do mv "$f" "${f// /_}"; done 2>/dev/null
	for f in input/vr/scaling/*\(*; do mv "$f" "${f//\(/_}"; done 2>/dev/null
	for f in input/vr/scaling/*\)*; do mv "$f" "${f//\)/_}"; done 2>/dev/null
	for f in input/vr/scaling/*\'*; do mv "$f" "${f//\'/_}"; done 2>/dev/null
	
	COUNT=`find input/vr/scaling -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' | wc -l`
	[ $loglevel -ge 1 ] && echo "Video Count: $COUNT"
	declare -i INDEX=0
	if [[ $COUNT -gt 0 ]] ; then
		VIDEOFILES=`find input/vr/scaling -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm'`
		for nextinputfile in $VIDEOFILES ; do
			INDEX+=1
			echo "$INDEX/$COUNT" >input/vr/scaling/BATCHPROGRESS.TXT
			echo "scaling" >user/default/comfyui_stereoscopic/.daemonstatus
			echo "video $INDEX of $COUNT" >>user/default/comfyui_stereoscopic/.daemonstatus
			newfn=${nextinputfile##*/}
			newfn=input/vr/scaling/${newfn//[^[:alnum:].-]/_}
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
				if test $duration -ge 600
				then
					echo -e $"\e[93mWarning:\e[0m long video (>600s) detected."
				fi
				if [ ! -d "$TVAI_BIN_DIR" ] ; then
					/bin/bash $SCRIPTPATH "$newfn" $override_active || exit 1
				
					status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
					if [ "$status" = "closed" ]; then
						echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
						exit 1
					fi
				else
					/bin/bash $SCRIPTPATH_TVAI "$newfn" $override_active || exit 1
				fi
			else
				echo -e $"\e[91mError:\e[0m prompting failed. Missing file: $newfn"
			fi			
			
		done
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
	fi
	rm -f input/vr/scaling/BATCHPROGRESS.TXT
	
	IMGFILES=`find input/vr/scaling -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' -o -name '*.webp'`
	COUNT=`find input/vr/scaling -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' -o -name '*.webp' | wc -l`
	declare -i INDEX=0
	[ $loglevel -ge 1 ] && echo "Image Count: $COUNT"
	if [[ $COUNT -gt 0 ]] ; then
		for nextinputfile in $IMGFILES ; do
			INDEX+=1
			echo "$INDEX/$COUNT" >input/vr/scaling/BATCHPROGRESS.TXT
			echo "scaling" >user/default/comfyui_stereoscopic/.daemonstatus
			echo "image $INDEX of $COUNT" >>user/default/comfyui_stereoscopic/.daemonstatus
			newfn=${nextinputfile##*/}
			newfn=input/vr/scaling/${newfn//[^[:alnum:].-]/_}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			mv "$nextinputfile" $newfn 
			
			if [[ "$newfn" == *_x?* ]]; then
				echo "Skipping $newfn (already scaled)"
				mv -fv $newfn output/vr/scaling
			elif [ -e "$newfn" ]
			then
				duration=-1
				override_active=1
				if [ -z "$OVERRIDESUBPATH" ]; then
					override_active=0
				fi

				/bin/bash $SCRIPTPATH2 "$newfn" $override_active || exit 1
				
				status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
				if [ "$status" = "closed" ]; then
					echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
					exit 1
				fi

			else
				echo -e $"\e[91mError:\e[0m prompting failed. Missing file: $newfn"
			fi			
			
		done
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
	fi
	rm -f input/vr/scaling/BATCHPROGRESS.TXT
	
	[ $loglevel -ge 0 ] && echo "Batch done."

fi

exit 0
