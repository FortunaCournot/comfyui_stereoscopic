#!/bin/sh
# Creates SBS videos in batch from all base videos placed in ComfyUI/input/sbs_in folder (input)

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).


# relative or abolute path of ComfyUI folder in your ComfyUI_windows_portable
# Default: Executed in ComfyUI folder
COMFYUIPATH=.
# relative to COMFYUIPATH:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/v2v_sbs_converter.sh 
SCRIPTPATH2=./custom_nodes/comfyui_stereoscopic/api/i2i_sbs_converter.sh 

cd $COMFYUIPATH

FREESPACE=$(df -khBG . | tail -n1 | awk '{print $4}')
FREESPACE=${FREESPACE%G}
MINSPACE=10
status=`true &>/dev/null </dev/tcp/127.0.0.1/8188 && echo open || echo closed`
if [ "$status" = "closed" ]; then
    echo "Error: ComfyUI not present. Ensure it is running on port 8188"
elif [[ $FREESPACE -lt $MINSPACE ]] ; then
	echo "Error: Less than $MINSPACE""G left on device: $FREESPACE""G"
elif test $# -ne 2; then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 depth_scale depth_offset"
    echo "E.g.: $0 1.0 0.0"
else
	depth_scale="$1"
	shift
	depth_offset="$1"
	shift

	for f in input/sbs_in/*\ *; do mv "$f" "${f// /_}"; done 2>/dev/null
	for f in input/sbs_in/*\(*; do mv "$f" "${f//\(/_}"; done 2>/dev/null
	for f in input/sbs_in/*\)*; do mv "$f" "${f//\)/_}"; done 2>/dev/null
	for f in input/sbs_in/*\'*; do mv "$f" "${f//\'/_}"; done 2>/dev/null

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
			
			TARGETPREFIX=${newfn##*/}
			if [[ "$TARGETPREFIX" = "*_SBS_LR" ]]; then
				echo "Skipping $newfn (already SBS)"
			elif [[ "$TARGETPREFIX" = "*_SBS_LR_4K" ]]; then
				echo "Skipping $newfn (already SBS)"
			elif [[ "$TARGETPREFIX" = "*_SBS_LR_DUB" ]]; then
				echo "Skipping $newfn (already SBS)"
			elif [[ "$TARGETPREFIX" = "*_SBS_LR_4K_DUB" ]]; then
				echo "Skipping $newfn (already SBS)"
			else
				/bin/bash $SCRIPTPATH $depth_scale $depth_offset "$newfn"
			fi
		done
		rm  -f input/sbs_in/BATCHPROGRESS.TXT 
	else
		echo "No .mp4 files found in input/sbs_in"
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
			
			if [ -e "$newfn" ]
			then
				/bin/bash $SCRIPTPATH2 $depth_scale $depth_offset "$newfn"
				
				status=`true &>/dev/null </dev/tcp/127.0.0.1/8188 && echo open || echo closed`
				if [ "$status" = "closed" ]; then
					echo "Error: ComfyUI not present. Ensure it is running on port 8188"
					exit
				fi
				
			else
				echo "Error: prompting failed. Missing file: $newfn"
			fi			
		done
		rm  -f input/sbs_in/BATCHPROGRESS.TXT 
				
	else
		echo "No image files (png|jpg|jpeg) found in input/sbs_in"
	fi	
	echo "Batch done."
fi
