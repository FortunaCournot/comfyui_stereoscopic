#!/bin/sh
# Upscales videos in batch from all base videos placed in ComfyUI/input/dubbing_in (input)
# 
# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).


# relative or abolute path of ComfyUI folder in your ComfyUI_windows_portable
# Default: Executed in ComfyUI folder
COMFYUIPATH=.
# relative to COMFYUIPATH:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/v2v_dubbing.sh 

cd $COMFYUIPATH

FREESPACE=$(df -khBG . | tail -n1 | awk '{print $4}')
FREESPACE=${FREESPACE%G}
MINSPACE=10
status=`true &>/dev/null </dev/tcp/127.0.0.1/8188 && echo open || echo closed`
if [ ! -d ./custom_nodes/ComfyUI-MMAudio ]; then
    echo "Warning: Custom nodes ComfyUI-MMAudio not present. Skipping."
elif [ ! -d ./models/mmaudio ]; then
    echo "Warning: Models for ComfyUI-MMAudio not present. Skipping."
elif [ "$status" = "closed" ]; then
    echo "Error: ComfyUI not present. Ensure it is running on port 8188"
elif [[ $FREESPACE -lt $MINSPACE ]] ; then
	echo "Error: Less than $MINSPACE""G left on device: $FREESPACE""G"
elif test $# -ne 0 ; then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 "
    echo "E.g.: $0 "
else
	
	COUNT=`find input/dubbing_in -maxdepth 1 -type f -name '*.mp4' | wc -l`
	declare -i INDEX=0
	if [[ $COUNT -gt 0 ]] ; then
		for nextinputfile in input/dubbing_in/*.mp4 ; do
			INDEX+=1
			echo "$INDEX/$COUNT" >input/dubbing_in/BATCHPROGRESS.TXT
			newfn=${nextinputfile//[^[:alnum:.]]/}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			mv "$nextinputfile" $newfn 
			
			/bin/bash $SCRIPTPATH "$newfn"
			
			status=`true &>/dev/null </dev/tcp/127.0.0.1/8188 && echo open || echo closed`
			if [ "$status" = "closed" ]; then
				echo "Error: ComfyUI not present. Ensure it is running on port 8188"
				exit
			fi
			
			echo "Waiting for queue to finish..."
			sleep 3  # Give some extra time to start...
			lastcount=""
			start=`date +%s`
			startjob=$start
			itertimemsg=""
			until [ "$queuecount" = "0" ]
			do
				sleep 1
				curl -silent "http://127.0.0.1:8188/prompt" >queuecheck.json
				queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
				if [[ "$lastcount" != "$queuecount" ]] && [[ -n "$lastcount" ]]
				then
					end=`date +%s`
					runtime=$((end-start))
					start=`date +%s`
					secs=$(("$queuecount * runtime"))
					eta=`printf '%02d:%02d:%02s\n' $((secs/3600)) $((secs%3600/60)) $((secs%60))`
					itertimemsg=", $runtime""s/prompt, ETA: $eta"
				fi
				lastcount="$queuecount"
					
				echo -ne "queuecount: $queuecount $itertimemsg         \r"
			done
			runtime=$((end-startjob))
			echo "done. duration: $runtime""s.                      "
			rm queuecheck.json
				
		done
	fi
	rm -f input/dubbing_in/BATCHPROGRESS.TXT
	echo "Batch done."

fi

