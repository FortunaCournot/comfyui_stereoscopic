#!/bin/sh
# Creates SBS videos in batch from all base videos placed in ComfyUI/input/vr/fullsbs folder (input)

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).


# relative or abolute path of ComfyUI folder in your ComfyUI_windows_portable
# Default: Executed in ComfyUI folder
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# relative to COMFYUIPATH:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/v2v_sbs_converter.sh 
SCRIPTPATH2=./custom_nodes/comfyui_stereoscopic/api/i2i_sbs_converter.sh 

cd $COMFYUIPATH

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

export CONFIGFILE
if [ -e $CONFIGFILE ] ; then
	loglevel=$(awk -F "=" '/loglevel/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
	[ $loglevel -ge 2 ] && set -x
    config_version=$(awk -F "=" '/config_version/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
	COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
	COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
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
elif test $# -ne 2; then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 depth_scale depth_offset"
    echo "E.g.: $0 1.0 0.0"
else
	mkdir -p output/vr/fullsbs

	depth_scale="$1"
	shift
	depth_offset="$1"
	shift

	#for file in input/vr/fullsbs/*' '*
	#do
	#	if [ -e "${file// /_}" ]
	#	then
	#		echo -e $"\e[91mError:\e[0m skipping $file as the renamed version already exists"
	#		mkdir -p input/vr/fullsbs/error
	#		mv -- "$file" input/vr/fullsbs/error
	#		continue
	#	fi
	#
	#	mv -- "$file" "${file// /_}"
	#done

	for f in input/vr/fullsbs/*\ *; do mv -- "$f" "${f// /_}"; done 2>/dev/null
	for f in input/vr/fullsbs/*\(*; do mv -- "$f" "${f//\(/_}"; done 2>/dev/null
	for f in input/vr/fullsbs/*\)*; do mv -- "$f" "${f//\)/_}"; done 2>/dev/null
	for f in input/vr/fullsbs/*\'*; do mv -- "$f" "${f//\'/_}"; done 2>/dev/null

	COUNT=`find input/vr/fullsbs -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' | wc -l`
	declare -i INDEX=0
	if [[ $COUNT -gt 0 ]] ; then
		VIDEOFILES=`find input/vr/fullsbs -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm'`
		for nextinputfile in $VIDEOFILES ; do
			INDEX+=1
			echo "$INDEX/$COUNT">input/vr/fullsbs/BATCHPROGRESS.TXT
			newfn=${nextinputfile##*/}
			newfn=input/vr/fullsbs/${newfn//[^[:alnum:].]/_}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			mv -- "$nextinputfile" $newfn 
			
			TARGETPREFIX=${newfn##*/}
			if [[ "$TARGETPREFIX" = "*_SBS_LR.*" ]]; then
				echo "Skipping $newfn (already SBS)"
				mkdir -p output/vr/fullsbs/final
				mv -fv -- $newfn output/vr/fullsbs/final
			elif [[ "$TARGETPREFIX" = "*_SBS_LR_4K.*" ]]; then
				echo "Skipping $newfn (already SBS)"
				mkdir -p output/vr/fullsbs/final
				mv -fv -- $newfn output/vr/fullsbs/final
			elif [[ "$TARGETPREFIX" = "*_SBS_LR_DUB.*" ]]; then
				echo "Skipping $newfn (already SBS)"
				mkdir -p output/vr/fullsbs/final
				mv -fv -- $newfn output/vr/fullsbs/final
			elif [[ "$TARGETPREFIX" = "*_SBS_LR_4K_DUB.*" ]]; then
				echo "Skipping $newfn (already SBS)"
				mkdir -p output/vr/fullsbs/final
				mv -fv -- $newfn output/vr/fullsbs/final
			else
				/bin/bash $SCRIPTPATH $depth_scale $depth_offset "$newfn"
			fi
		done
		rm  -f input/vr/fullsbs/BATCHPROGRESS.TXT 
	fi	
	
	IMGFILES=`find input/vr/fullsbs -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG'`
	COUNT=`find input/vr/fullsbs -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
	INDEX=0
	rm -f intermediateimagefiles.txt
	if [[ $COUNT -gt 0 ]] ; then
		for nextinputfile in $IMGFILES ; do
			if [ ! -e $nextinputfile ] ; then
				echo -e $"\e[91mError:\e[0m File removed. Batch task terminated."
				exit 1
			fi
			INDEX+=1
			echo "$INDEX/$COUNT">input/vr/fullsbs/BATCHPROGRESS.TXT
			newfn=${nextinputfile##*/}
			newfn=input/vr/fullsbs/${newfn//[^[:alnum:].]/_}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			mv -- "$nextinputfile" $newfn 
			
			if [[ "$newfn" == *_SBS_LR* ]]; then
				echo "Skipping $newfn (already SBS)"
				mkdir -p output/vr/fullsbs
				mv -fv -- $newfn output/vr/fullsbs
			elif [ -e "$newfn" ]
			then
				/bin/bash $SCRIPTPATH2 $depth_scale $depth_offset "$newfn"
				
				status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
				if [ "$status" = "closed" ]; then
					echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
					exit 1
				fi
				
			else
				echo -e $"\e[91mError:\e[0m prompting failed. Missing file: $newfn"
			fi			
		done
		rm  -f input/vr/fullsbs/BATCHPROGRESS.TXT 
				
	fi	
	echo "Batch done."
fi
exit 0
