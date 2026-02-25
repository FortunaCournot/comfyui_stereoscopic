#!/bin/sh
#
# batch_concat.sh || exit 1
#
# Reverse a video (input) and concat them. For multiple input videos (I2V: all must have same start frame, same resolution, etc. ) do same for each and concat all with silence audio.
#
# Copyright (c) 2025 Fortuna Cournot. MIT License. www.3d-gallery.org

onExit() {
	exit_code=$?
	exit $exit_code
}
trap onExit EXIT

# abolute path of ComfyUI folder in your ComfyUI_windows_portable. ComfyUI server is not used.
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# set FFMPEGPATHPREFIX if ffmpeg binary is not in your enviroment path
FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX=/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}


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

	mkdir -p output/vr/concat/intermediate
	mkdir -p input/vr/concat/done
	
	echo -ne $"\e[97m\e[1m=== CONCAT READY - PRESS RETURN TO START ===\e[0m" ; read forgetme ; echo "starting..."

	for f in input/vr/concat/*\ *; do mv -- "$f" "${f// /_}"; done 2>/dev/null

	if [ -z "$COMFYUIPATH" ]; then
		echo "Error: COMFYUIPATH not set in $(basename \"$0\") (cwd=$(pwd)). Start script from repository root."; exit 1;
	fi
	LIB_FS="$COMFYUIPATH/custom_nodes/comfyui_stereoscopic/api/lib_fs.sh"
	if [ -f "$LIB_FS" ]; then
		. "$LIB_FS" || { echo "Error: failed to source canonical $LIB_FS in $(basename \"$0\") (cwd=$(pwd))"; exit 1; }
	else
		echo "Error: required lib_fs not found at canonical path: $LIB_FS"; exit 1;
	fi
	COUNT=$(count_files_with_exts "input/vr/concat" mp4)
	INDEX=0
	if [[ $COUNT -gt 0 ]] ; then
		echo "concat" >user/default/comfyui_stereoscopic/.daemonstatus
		# helper: process current group stored in IMGANDVIDFILES
		process_group() {
			echo "" >output/vr/concat/intermediate/mylist.txt
			INDEX=0
			for nextinputfile in $IMGANDVIDFILES ; do
				[ -e "$nextinputfile" ] || continue
				INDEX=$((INDEX+1))
				newfn=part_$INDEX.mp4
				cp "$nextinputfile" output/vr/concat/intermediate/$newfn 
				if [ -e "output/vr/concat/intermediate/$newfn" ]
				then
					echo "file $newfn" >>output/vr/concat/intermediate/mylist.txt
				else
					echo -e $"\e[91mError:\e[0m prompting failed. Missing file: output/vr/concat/intermediate/$newfn"
					exit 1
				fi
			done
			NOW=$( date '+%F_%H%M' )
			BASE=${nextinputfile##*/}
			BASE=${BASE%_*}
			SUFFIX=""
			if echo "$IMGANDVIDFILES" | grep -q "_SBS_LR" ; then
				SUFFIX="_SBS_LR"
			fi
			TARGET=output/vr/concat/${BASE}-${NOW}${SUFFIX}.mp4
			cd output/vr/concat/intermediate
			echo -ne "Concat (${BASE})...                             \r"
			nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i mylist.txt -c copy result.mp4
			if [ ! -e "result.mp4" ]; then echo -e $"\e[91mError:\e[0m failed to create result.mp4" && exit 1 ; fi
			cd ../../../..
			mv -f output/vr/concat/intermediate/result.mp4 "$TARGET"
			# move only the files belonging to this group into done
			for mvf in $IMGANDVIDFILES ; do
				mv "$mvf" input/vr/concat/done/ 2>/dev/null || true
			done
			if [ -e "$TARGET" ]; then
				rm -f output/vr/concat/intermediate/*
			else
				echo -e $"\e[91mError:\e[0m Failed to create target file $TARGET"
			fi
			echo -e $"\e[92mdone (${BASE}).\e[0m                            "
		}
		
		# build group keys by replacing the numeric token (_NNN_) with _NUM_
		KEYS=$(find input/vr/concat -maxdepth 1 -type f -name '*.mp4' -printf '%f\n' | grep -E '_[0-9]{3,}_' | sed -E 's/_([0-9]{3,})_/_NUM_/' | sort -u)
		for KEY in $KEYS ; do
			# create a glob pattern by replacing the marker back to wildcard
			PATTERN=$(echo "$KEY" | sed 's/_NUM_/_*_/')
			IMGANDVIDFILES=$(find input/vr/concat -maxdepth 1 -type f -name "$PATTERN" | sort)
			[ -z "$IMGANDVIDFILES" ] && continue
			process_group
		done
		# process rest (files without the numeric _NNN_ token)
		RESTFILES=$(find input/vr/concat -maxdepth 1 -type f -name '*.mp4' | sort | grep -Ev '_[0-9]{3,}_' || true)
		if [ -n "$RESTFILES" ] ; then
			IMGANDVIDFILES=$RESTFILES
			process_group
		fi
	else
		echo -e $"\e[91mError:\e[0m COUNT=$COUNT: $(find input/vr/concat -maxdepth 1 -type f -name '*.mp4')"
	fi
	echo "Batch ($COUNT) done.                             "
fi
exit 0
