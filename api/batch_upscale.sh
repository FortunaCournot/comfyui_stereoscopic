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

if test $# -ne 0 -a $# -ne 1
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 "
    echo "E.g.: $0 "
else
	cd $COMFYUIPATH

	SIGMA=1.0
	if test $# -eq 1
	then
		SIGMA=$1
	fi

	COUNT=`find input/upscale_in -maxdepth 1 -type f -name '*.mp4' | wc -l`
	declare -i INDEX=0
	for nextinputfile in input/upscale_in/*.mp4 ; do
		INDEX+=1
		echo "$INDEX/$COUNT" >input/upscale_in/BATCHPROGRESS.TXT
		newfn=${nextinputfile//[^[:alnum:.]]/}
		newfn=${newfn// /_}
		newfn=${newfn//\(/_}
		newfn=${newfn//\)/_}
		mv "$nextinputfile" $newfn 
		
		/bin/bash $SCRIPTPATH "$newfn"
	done
	rm input/upscale_in/BATCHPROGRESS.TXT
	echo "Batch done."

fi

