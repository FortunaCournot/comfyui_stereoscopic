#!/bin/sh
#
# v2v_dubbing.sh || exit 1
#
# dubbes a base video (input) by mmaudio and places result under ComfyUI/output/vr/tasks folder.
#
# Copyright (c) 2025 FortunaCournot. MIT License.

# This ComfyUI API script needs addional custom node packages: 
#  MMAudio, Florence2

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).
# Prerequisite: Configured path variables below.
# Prerequisite: Git Bash installed. Call this script in Git Bash

# - It will split the input video into segements,
# - It queues dubbing workflows via api,
# - Creates a shell script for concating resulting audio segments and dubbes video
# - Waits until comfyui is done, then call created script.

# either start this script in ComfyUI folder or enter absolute path of ComfyUI folder in your ComfyUI_windows_portable here
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi

# API relative to COMFYUIPATH, or absolute path:
COMFYUIPATH=`realpath $(dirname "$0")/../../../..`


if test $# -ne 3 
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 jsonblueprintpath taskname inputfile"
else
	
	cd $COMFYUIPATH

	CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

	NOLINE=-ne
	
	export CONFIGFILE
	if [ -e $CONFIGFILE ] ; then
		loglevel=$(awk -F "=" '/loglevel/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
		[ $loglevel -ge 2 ] && set -x
		[ $loglevel -ge 2 ] && NOLINE="" ; echo $NOLINE
		config_version=$(awk -F "=" '/config_version/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
#		COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
#		COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
#		export COMFYUIHOST COMFYUIPORT
	else
		echo -e $"\e[91mError:\e[0m No config!?"
		exit 1
	fi

	# set FFMPEGPATHPREFIX if ffmpeg binary is not in your enviroment path
	FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}

	EXIFTOOLBINARY=$(awk -F "=" '/EXIFTOOLBINARY/ {print $2}' $CONFIGFILE) ; EXIFTOOLBINARY=${EXIFTOOLBINARY:-""}

#	status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
#	if [ "$status" = "closed" ]; then
#		echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
#		exit 1
#	fi

	# Use Systempath for python by default, but set it explictly for comfyui portable.
	PYTHON_BIN_PATH=
	if [ -d "../python_embeded" ]; then
	  PYTHON_BIN_PATH=../python_embeded/
	fi

	BLUEPRINTCONFIG="$1"
	shift
	TASKNAME="$1"
	shift
	INPUT="$1"
	shift

	PROGRESS=" "
	if [ -e input/vr/tasks/BATCHPROGRESS.TXT ]
	then
		PROGRESS=`cat input/vr/tasks/BATCHPROGRESS.TXT`" "
	fi
	regex="[^/]*$"
	echo "========== $PROGRESS""$BLUEPRINTNAME "`echo $INPUT | grep -oP "$regex"`" =========="
	
	TARGETPREFIX=${INPUT##*/}
	INPUT=`realpath "$INPUT"`
	TARGETPREFIX=output/vr/tasks/intermediate/${TARGETPREFIX%.*}
	mkdir -p output/vr/tasks/intermediate
	FINALTARGETFOLDER=`realpath "output/vr/tasks/$TASKNAME"`
	mkdir -p $FINALTARGETFOLDER
	
	echo "Final: $FINALTARGETFOLDER"
	echo "task done."

fi
exit 0

