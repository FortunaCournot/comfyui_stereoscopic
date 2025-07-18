#!/bin/sh
# Upscales videos in batch from all base videos placed in ComfyUI/input/upscale_in (input)
# 
# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).


# relative or abolute path of ComfyUI folder in your ComfyUI_windows_portable
# Default: Executed in ComfyUI folder
COMFYUIPATH=.
# relative to COMFYUIPATH:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/v2m_dubbing.sh 

cd $COMFYUIPATH

echo "Work in progress."
exit

FREESPACE=$(df -khBG . | tail -n1 | awk '{print $4}')
FREESPACE=${FREESPACE%G}
MINSPACE=10
status=`true &>/dev/null </dev/tcp/127.0.0.1/8188 && echo open || echo closed`
if [ "$status" = "closed" ]; then
    echo "Error: ComfyUI not present. Ensure it is running on port 8188"
elif [[ $FREESPACE -lt $MINSPACE ]] ; then
	echo "Error: Less than $MINSPACE""G left on device: $FREESPACE""G"
elif test $# -ne 0 ; then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 "
    echo "E.g.: $0 "
else
	COUNT=`find input/upscale_in -maxdepth 1 -type f -name '*.mp4' | wc -l`
	declare -i INDEX=0
	if [[ $COUNT -gt 0 ]] ; then
		for nextinputfile in input/dubbing_in/*.mp4 ; do
			INDEX+=1
			echo "$INDEX/$COUNT" >input/upscale_in/BATCHPROGRESS.TXT
			newfn=${nextinputfile//[^[:alnum:.]]/}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			mv "$nextinputfile" $newfn 
			
			TESTAUDIO=`"$FFMPEGPATH"ffprobe -i "$newfn" -show_streams -select_streams a -loglevel error`
			if [[ $TESTAUDIO =~ "[STREAM]" ]]; then
				/bin/bash $SCRIPTPATH "$newfn"
				
				echo "Waiting for queue to finish..."
				sleep 4  # Give some extra time to start...
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
				
				#TODO: ADD GENERATED SOUND TO VIDEO
				#nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 -i "$newfn" -y -c:v copy -c:a aac -shortest tmpvidwithaudio.mp4

				# save input
				mkdir -p input/dubbing_in/done
				mv $newfn input/dubbing_in/done
				
				# move output to next step in pipeline
				mv tmpvidwithaudio.mp4 $newfn
				mv $newfn input/upscale_in
			else
			echo "Audio found, skipping $newfn"
				# directly move input to next step in pipeline
				mv $newfn input/upscale_in
			fi
			
		done
	fi
	rm -f input/upscale_in/BATCHPROGRESS.TXT
	echo "Batch done."

fi

