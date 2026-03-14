#!/bin/sh
#
# v2v_singleloop.sh || exit 1
#
# Reverse a video (input) and concat them. For multiple input videos (I2V: all must have same start frame, same resolution, etc. ) do same for each and concat all with silence audio.
#
# Copyright (c) 2025 Fortuna Cournot. MIT License. www.3d-gallery.org

onExit() {
	exit_code=$?
	exit $exit_code
}
trap onExit EXIT

SAFE_BASENAME_MAXLEN=${SAFE_BASENAME_MAXLEN:-72}

normalize_rename_path() {
	local path="$1"
	local max_len="${2:-$SAFE_BASENAME_MAXLEN}"
	local dir file stem suffix
	dir="${path%/*}"
	[ "$dir" = "$path" ] && dir=""
	file="${path##*/}"
	stem="$file"
	suffix=""
	if [[ "$file" == *.* && "$file" != .* ]]; then
		suffix=".${file##*.}"
		stem="${file%.*}"
	fi
	stem="${stem//[^[:alnum:].-]/_}"
	[ -z "$stem" ] && stem="file"
	if [ "${#stem}" -gt "$max_len" ] ; then
		stem="${stem:0:$max_len}"
	fi
	if [ -n "$dir" ] ; then
		printf '%s/%s%s' "$dir" "$stem" "$suffix"
	else
		printf '%s%s' "$stem" "$suffix"
	fi
}

# abolute path of ComfyUI folder in your ComfyUI_windows_portable. ComfyUI server is not used.
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# set FFMPEGPATHPREFIX if ffmpeg binary is not in your enviroment path
# relative to COMFYUIPATH:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/v2v_singleloop.sh 

FREESPACE=$(df -khBG . | tail -n1 | awk '{print $4}')
FREESPACE=${FREESPACE%G}
MINSPACE=10
status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
if test $# -gt 0
then
    echo "Usage: $0 "
    echo "E.g.: $0"
elif [[ $FREESPACE -lt $MINSPACE ]] ; then
	echo -e $"\e[91mError:\e[0m Less than $MINSPACE""G left on device: $FREESPACE""G"
else
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

	EXIFTOOLBINARY=$(awk -F "=" '/EXIFTOOLBINARY=/ {print $2}' $CONFIGFILE) ; EXIFTOOLBINARY=${EXIFTOOLBINARY:-""}
	
	mkdir -p output/vr/singleloop/intermediate
	mkdir -p input/vr/singleloop/done
	
	shopt -s nullglob
	for f in input/vr/singleloop/*; do
		[ -e "$f" ] || continue
		new=$(normalize_rename_path "$f")
		[ "$new" = "$f" ] || mv -- "$f" "$new"
	done 2>/dev/null
	
	if [ -z "$COMFYUIPATH" ]; then
		echo "Error: COMFYUIPATH not set in $(basename \"$0\") (cwd=$(pwd)). Start script from repository root."; exit 1;
	fi
	LIB_FS="$COMFYUIPATH/custom_nodes/comfyui_stereoscopic/api/lib_fs.sh"
	if [ -f "$LIB_FS" ]; then
		. "$LIB_FS" || { echo "Error: failed to source canonical $LIB_FS in $(basename \"$0\") (cwd=$(pwd))"; exit 1; }
	else
		echo "Error: required lib_fs not found at canonical path: $LIB_FS"; exit 1;
	fi
	COUNT=$(count_files_with_exts "input/vr/singleloop" mp4 webm)
	declare -i INDEX=0
	if [[ $COUNT -gt 0 ]] ; then
		VIDFILES=`find input/vr/singleloop -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm'`
		for nextinputfile in $VIDFILES ; do
			[ -e "$nextinputfile" ] || continue
			[ -e user/default/comfyui_stereoscopic/.pipelinepause ] && exit 0
			INDEX+=1
			echo "$INDEX/$COUNT" >input/vr/singleloop/BATCHPROGRESS.TXT
			echo "singleloop" >user/default/comfyui_stereoscopic/.daemonstatus
			echo "video $INDEX of $COUNT: ${nextinputfile##*/}" >>user/default/comfyui_stereoscopic/.daemonstatus
			newfn=$(normalize_rename_path "input/vr/singleloop/${nextinputfile##*/}")
			mv "$nextinputfile" "$newfn" 
			
			if [ -e "$newfn" ]
			then
				TARGETPREFIX=${newfn##*/}
				TARGETPREFIX=${TARGETPREFIX%.*}
				TARGETPREFIX=${TARGETPREFIX//"_dub"/}
				INTERMEDIATEFILE=`realpath "output/vr/singleloop/intermediate/$TARGETPREFIX""_loop.mp4"`
				/bin/bash $SCRIPTPATH  $INTERMEDIATEFILE `realpath "$newfn"`
				
				if [ -e $INTERMEDIATEFILE ]
				then
					[ -e "$EXIFTOOLBINARY" ] && "$EXIFTOOLBINARY" -all= -tagsfromfile "$newfn" -all:all -overwrite_original $INTERMEDIATEFILE && echo "tags copied."
					mv -- $INTERMEDIATEFILE output/vr/singleloop/$TARGETPREFIX"_loop.mp4"
					mv -- $newfn input/vr/singleloop/done
				else
					echo -e $"\e[91mError:\e[0m creating loop failed. Missing file: output/vr/singleloop/intermediate/$TARGETPREFIX""_loop.mp4"
					mkdir -p input/vr/singleloop/error
					mv -- $newfn input/vr/singleloop/error
				fi
			else
				echo -e $"\e[91mError:\e[0m prompting failed. Missing file: $newfn"
			fi			
			
		done
	fi
	rm -f input/vr/singleloop/BATCHPROGRESS.TXT
	echo "Batch done.                             "
fi
exit 0
