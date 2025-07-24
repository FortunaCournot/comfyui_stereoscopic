#!/bin/sh
# Upscales videos in batch from all base videos placed in ComfyUI/input/vr/scaling (input)
# 
# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).


# relative or abolute path of ComfyUI folder in your ComfyUI_windows_portable
# Default: Executed in ComfyUI folder
COMFYUIPATH=.
# relative to COMFYUIPATH:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/v2v_upscale_downscale.sh 

cd $COMFYUIPATH

FREESPACE=$(df -khBG . | tail -n1 | awk '{print $4}')
FREESPACE=${FREESPACE%G}
MINSPACE=10
status=`true &>/dev/null </dev/tcp/127.0.0.1/8188 && echo open || echo closed`
if [ "$status" = "closed" ]; then
    echo "Error: ComfyUI not present. Ensure it is running on port 8188"
elif [[ $FREESPACE -lt $MINSPACE ]] ; then
	echo "Error: Less than $MINSPACE""G left on device: $FREESPACE""G"
elif test $# -ne 0 -a $# -ne 1; then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 [OVERRIDESUBPATH]"
    echo "E.g.: $0 /override"
else
	if test $# -eq 1; then
		OVERRIDESUBPATH="$1"
		shift
		
		mv -fv "input/vr/scaling""$OVERRIDESUBPATH"/*.mp4 input/vr/scaling
	fi
	
	COUNT=`find input/vr/scaling -maxdepth 1 -type f -name '*.mp4' | wc -l`
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
				if [ -z "$OVERRIDESUBPATH" ]; then
					duration=`"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=nw=1:nk=1 $newfn`
					duration=${duration%.*}
				fi
				if test $duration -ge 10
				then
					echo "long video (>10s) detected. Ignored; call $SCRIPTPATH directly or move it to input/vr/scaling$OVERRIDESUBPATH. Skipping $newfn"
					sleep 10	# file will stay - this cause daemon to loop foreve - ensure user can read message
				else
					/bin/bash $SCRIPTPATH "$newfn"
					
					status=`true &>/dev/null </dev/tcp/127.0.0.1/8188 && echo open || echo closed`
					if [ "$status" = "closed" ]; then
						echo "Error: ComfyUI not present. Ensure it is running on port 8188"
						exit
					fi
				fi
			else
				echo "Error: prompting failed. Missing file: $newfn"
			fi			
			
		done
	fi
	rm -f input/vr/scaling/BATCHPROGRESS.TXT
	echo "Batch done."

fi

