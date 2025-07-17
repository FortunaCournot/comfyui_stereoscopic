#!/bin/sh
# Creates SBS videos in batch from all base videos placed in ComfyUI/input/sbs_in folder (input)
# The end condition is checked automatic,  If queue gets empty the batch_concat.sh script is called. 

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).


# relative or abolute path of ComfyUI folder in your ComfyUI_windows_portable
# Default: Executed in ComfyUI folder
COMFYUIPATH=.
# relative to COMFYUIPATH:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/v2v_sbs_converter.sh 
SCRIPTPATH2=./custom_nodes/comfyui_stereoscopic/api/i2i_sbs_converter.sh 
CONCATBATCHSCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/batch_concat.sh 

status=`true &>/dev/null </dev/tcp/127.0.0.1/8188 && echo open || echo closed`
if [ "$status" = "closed" ]; then
    echo "Error: ComfyUI not present. Ensure it is running on port 8188"
elif test $# -ne 2
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 depth_scale depth_offset"
    echo "E.g.: $0 1.0 0.0"
else
	cd $COMFYUIPATH

	depth_scale="$1"
	shift
	depth_offset="$1"
	shift

	COUNT=`find input/sbs_in -maxdepth 1 -type f -name '*.mp4' | wc -l`
	declare -i INDEX=0
	MP4FILES=input/sbs_in/*.mp4
	if [[ $COUNT -gt 0 ]] ; then
		for nextinputfile in $MP4FILES ; do
			INDEX+=1
			echo "$INDEX/$COUNT">input/sbs_in/BATCHPROGRESS.TXT
			newfn=${nextinputfile//[^[:alnum:.]]/}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			mv "$nextinputfile" $newfn 
			
			/bin/bash $SCRIPTPATH $depth_scale $depth_offset "$newfn"
		done
		rm  -f input/sbs_in/BATCHPROGRESS.TXT 
	fi	
	
	IMGFILES=`find input/sbs_in -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG'`
	COUNT=`find input/sbs_in -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
	INDEX=0
	rm -f intermediateimagefiles.txt
	if [[ $COUNT -gt 0 ]] ; then
		for nextinputfile in $IMGFILES ; do
			INDEX+=1
			echo "$INDEX/$COUNT">input/sbs_in/BATCHPROGRESS.TXT
			newfn=${nextinputfile//[^[:alnum:.]]/}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			mv "$nextinputfile" $newfn 
			
			/bin/bash $SCRIPTPATH2 $depth_scale $depth_offset "$newfn"
		done
		rm  -f input/sbs_in/BATCHPROGRESS.TXT 
		
		echo "Waiting one minute for first prompt in queue to finish..."
		lastcount=""
		start=`date +%s`
		sleep 60  # Give some extra time to start...
		end=`date +%s`
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
		
		while read INTERMEDIATE; do
			echo "Finalizing $INTERMEDIATE ..."
			
			if [ -e "$INTERMEDIATE" ]
			then
				FINALTARGET="${INTERMEDIATE%_00001_.png}"".png"
				echo "Moving to $FINALTARGET"
				mv "$INTERMEDIATE" "$FINALTARGET"
			else
				echo "Warning: File not found: $INTERMEDIATE"
			fi
		done <intermediateimagefiles.txt
		rm intermediateimagefiles.txt

	fi	
	echo "Batch done."
fi
