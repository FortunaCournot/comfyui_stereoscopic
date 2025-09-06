#!/bin/sh
# interpolates video fps in batch from all base videos placed in ComfyUI/input/vr/interpolate (input)
# 
# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).


# relative or abolute path of ComfyUI folder in your ComfyUI_windows_portable
# Default: Executed in ComfyUI folder
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# relative to COMFYUIPATH:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/v2v_interpolate.sh 
#SCRIPTPATH2=./custom_nodes/comfyui_stereoscopic/api/i2i_interpolate.sh 
SCRIPTPATH_TVAI=./custom_nodes/comfyui_stereoscopic/api/v2v_interpolate_tvai.sh 

cd $COMFYUIPATH

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

export CONFIGFILE
if [ -e $CONFIGFILE ] ; then
	loglevel=$(awk -F "=" '/loglevel=/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
	[ $loglevel -ge 2 ] && set -x
    config_version=$(awk -F "=" '/config_version=/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
	COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST=/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
	COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT=/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
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
elif test $# -ne 0; then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0"
    echo "E.g.: $0"
else
	mkdir -p output/vr/interpolate/intermediate

	multiplicator=2

	TVAI_BIN_DIR=$(awk -F "=" '/TVAI_BIN_DIR=/ {print $2}' $CONFIGFILE | head -n 1) ; TVAI_BIN_DIR=${TVAI_BIN_DIR:-""}

	# Use Systempath for python by default, but set it explictly for comfyui portable.
	PYTHON_BIN_PATH=
	if [ -d "../python_embeded" ]; then
	  PYTHON_BIN_PATH=../python_embeded/
	fi
	
	echo -ne $"\e[91m"
	VRAM=`"$PYTHON_BIN_PATH"python.exe custom_nodes/comfyui_stereoscopic/api/python/get_vram.py`
	echo -ne $"\e[0m"	
	if [ -z "$VRAM" ] ; then VRAM=0 ; fi
	
	for f in input/vr/interpolate/*\ *; do mv "$f" "${f// /_}"; done 2>/dev/null
	for f in input/vr/interpolate/*\(*; do mv "$f" "${f//\(/_}"; done 2>/dev/null
	for f in input/vr/interpolate/*\)*; do mv "$f" "${f//\)/_}"; done 2>/dev/null
	for f in input/vr/interpolate/*\'*; do mv "$f" "${f//\'/_}"; done 2>/dev/null
	
	COUNT=`find input/vr/interpolate -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' | wc -l`
	[ $loglevel -ge 1 ] && echo "Video Count: $COUNT"
	declare -i INDEX=0
	if [[ $COUNT -gt 0 ]] ; then
		VIDEOFILES=`find input/vr/interpolate -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm'`
		for nextinputfile in $VIDEOFILES ; do
			INDEX+=1
			echo "$INDEX/$COUNT" >input/vr/interpolate/BATCHPROGRESS.TXT
			echo "interpolate" >user/default/comfyui_stereoscopic/.daemonstatus
			echo "video $INDEX of $COUNT" >>user/default/comfyui_stereoscopic/.daemonstatus
			newfn=${nextinputfile##*/}
			newfn=input/vr/interpolate/${newfn//[^[:alnum:].-]/_}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			mv "$nextinputfile" $newfn 
			
			if [ -e "$newfn" ]
			then
				if [ ! -e "$TVAI_BIN_DIR" ] ; then
					/bin/bash $SCRIPTPATH "$multiplicator" "$VRAM" "$newfn" || exit 1
				
					status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
					if [ "$status" = "closed" ]; then
						echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
						exit 1
					fi
				else
					/bin/bash $SCRIPTPATH_TVAI "$multiplicator" "$VRAM" "$newfn"  || exit 1
				fi
			else
				echo -e $"\e[91mError:\e[0m prompting failed. Missing file: $newfn"
			fi			
			
		done
	fi
	rm -f input/vr/interpolate/BATCHPROGRESS.TXT
	
	
	[ $loglevel -ge 0 ] && echo "Batch done."

fi

exit 0
