#!/bin/sh
# Upscales videos in batch from all base videos placed in ComfyUI/input/upscale_in (input)
# The end condition is checked automatic,  If queue gets empty the batch_concat.sh script is called. 
# 
# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).


# relative or abolute path of ComfyUI folder in your ComfyUI_windows_portable
# Default: Executed in ComfyUI folder
COMFYUIPATH=.
# relative to COMFYUIPATH:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/v2v_upscale.sh 
CONCATBATCHSCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/batch_concat.sh 

if test $# -ne 0
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 "
    echo "E.g.: $0 "
else
	cd $COMFYUIPATH

	for nextinputfile in input/upscale_in/*.mp4 ; do
		newfn=${nextinputfile//[^[:alnum:.]]/}
		newfn=${newfn// /_}
		newfn=${newfn//\(/_}
		newfn=${newfn//\)/_}
		mv "$nextinputfile" $newfn 
		
		/bin/bash $SCRIPTPATH "$newfn"
	done

	
	echo "Waiting for queue to finish..."
	sleep 10   # Give some time to start...
	queuecount=""
    until [ "$queuecount" = "0" ]
	do
		sleep 1
		curl -silent "http://127.0.0.1:8188/prompt" >queuecheck.json
		queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
		echo -ne "queuecount: $queuecount  \r"
	done
	echo -ne '\ndone.'
	rm queuecheck.json
	$CONCATBATCHSCRIPTPATH	
fi

