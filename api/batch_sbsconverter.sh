#!/bin/sh
# Creates SBS videos in batch from all base videos placed in ComfyUI/input/sbs_in folder (input)
# The end condition is checked automatic,  If queue gets empty the batch_concat.sh script is called. 

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).


# relative or abolute path of ComfyUI folder in your ComfyUI_windows_portable
# Default: Executed in ComfyUI folder
COMFYUIPATH=.
# relative to COMFYUIPATH:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/v2v_sbs_converter.sh 
CONCATBATCHSCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/batch_concat.sh 

if test $# -ne 2
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
	for nextinputfile in input/sbs_in/*.mp4 ; do
		INDEX+=1
		echo "$INDEX/$COUNT">input/sbs_in/BATCHPROGRESS.TXT
		newfn=${nextinputfile//[^[:alnum:.]]/}
		newfn=${newfn// /_}
		newfn=${newfn//\(/_}
		newfn=${newfn//\)/_}
		mv "$nextinputfile" $newfn 
		
		/bin/bash $SCRIPTPATH $depth_scale $depth_offset "$newfn"
	done	
	rm input/sbs_in/BATCHPROGRESS.TXT
	echo "Batch done."
fi

