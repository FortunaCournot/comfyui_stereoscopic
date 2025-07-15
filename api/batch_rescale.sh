#!/bin/sh
# Rescales videos in batch from all base videos placed in ComfyUI/input/upscale_in (input)
# The end condition is checked automatic,  If queue gets empty the batch_concat.sh script is called. 
# 
# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).


# relative or abolute path of ComfyUI folder in your ComfyUI_windows_portable
# Default: Executed in ComfyUI folder
COMFYUIPATH=.
# relative to COMFYUIPATH:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/v2v_rescale.sh 
CONCATBATCHSCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/batch_concat.sh 

if test $# -ne 0 -a $# -ne 1 
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 [sigma]"
    echo "E.g.: $0 0.2"
else
	cd $COMFYUIPATH

	SIGMA=0.2
	
	if test $# -eq 1
	then
		SIGMA=$1
		shift	
	fi

	COUNT=`find input/upscale_in -maxdepth 1 -type f -name '*.mp4' | wc -l`
	declare -i INDEX=0
	MP4FILES=input/upscale_in/*.mp4
	if [[ $COUNT -gt 0 ]] ; then
		for nextinputfile in $MP4FILES ; do
			INDEX+=1
			echo "$INDEX/$COUNT">input/upscale_in/BATCHPROGRESS.TXT
			newfn=${nextinputfile//[^[:alnum:.]]/}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			mv "$nextinputfile" $newfn $SIGMA
			
			/bin/bash $SCRIPTPATH "$newfn"
		done
	fi
	rm -f input/upscale_in/BATCHPROGRESS.TXT
	echo "Batch done."

fi

