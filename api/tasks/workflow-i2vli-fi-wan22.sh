#!/bin/sh
#
# workflow-i2v-fi-wan22.sh
#
# executes a i2v workflow for a start image (input) and places video result under ComfyUI/output/vr/tasks folder.
#
# Copyright (c) 2025 Fortuna Cournot. MIT License. www.3d-gallery.org

# This ComfyUI API script needs addional custom node packages: 
#  MMAudio, Florence2

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).
# Prerequisite: Configured path variables below.
# Prerequisite: Git Bash installed. Call this script in Git Bash

# - It queues workflows via api,
# - Waits until comfyui is done, then call created script.

# either start this script in ComfyUI folder or enter absolute path of ComfyUI folder in your ComfyUI_windows_portable here
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi

assertlimit() {
    mode_upperlimit=$1
    kv=$2
	
    key=${kv%=*}
    value2=$(( ${kv#*=} ))

    temp=`grep "$key" output/vr/tasks/intermediate/probe.txt`
	temp=${temp#*:}
    temp="${temp%,*}"
	temp="${temp%\"*}"
    temp="${temp#*\"}"
	value1=$(( $temp ))

    if [ "$mode_upperlimit" != "true" ] ; then tmp="$value1" ; value1="$value2" ; value2="$tmp" ; fi
	
    if [ "$value1" -gt "$value2" ] ; then
		echo -e $"\e[32mLimit already fullfilled:\e[0m $key"": $value1 > $value2"". Skip processing and forwarding to output."
		mv -vf -- "$INPUT" "$FINALTARGETFOLDER"
		exit 0
	else
		echo "Condition met. $key"": $value1 <= $value2"
	fi
} 


COMFYUIPATH=`realpath $(dirname "$0")/../../../..`

if test $# -ne 3 
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 jsonblueprintpath taskname inputfile"
else
	
	cd $COMFYUIPATH

	CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

	# API relative to COMFYUIPATH, or absolute path:
	SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/python/workflow/i2v_fi_wan22.py

	NOLINE=-ne
	
	export CONFIGFILE
	if [ -e $CONFIGFILE ] ; then
		loglevel=$(awk -F "=" '/loglevel=/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
		[ $loglevel -ge 2 ] && set -x
		[ $loglevel -ge 2 ] && NOLINE="" ; echo $NOLINE
		config_version=$(awk -F "=" '/config_version=/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
		COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST=/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
		COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT=/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
		export COMFYUIHOST COMFYUIPORT
	else
		echo -e $"\e[91mError:\e[0m No config!?"
		exit 1
	fi

	# set FFMPEGPATHPREFIX if ffmpeg binary is not in your enviroment path
	FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX=/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}

	EXIFTOOLBINARY=$(awk -F "=" '/EXIFTOOLBINARY=/ {print $2}' $CONFIGFILE) ; EXIFTOOLBINARY=${EXIFTOOLBINARY:-""}

	until [ "$queuecount" = "0" ]
	do
		sleep 1
		
	  status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
	  if [ "$status" = "open" ]; then
      curl -silent "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json
      queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
    else
		  echo -ne "Waiting for empty queue        \r"
	  fi
	done
  queuecount=
  echo "                                   "
  
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
	echo "========== $PROGRESS"`echo $INPUT | grep -oP "$regex"`" =========="
	
  rm -rf -- output/vr/tasks/intermediate
	mkdir -p  output/vr/tasks/intermediate

	`"$FFMPEGPATHPREFIX"ffprobe -hide_banner -v error -select_streams V:0 -show_entries stream=bit_rate,width,height,r_frame_rate,duration,nb_frames -of json -i "$INPUT" >output/vr/tasks/intermediate/probe.txt`
	`"$FFMPEGPATHPREFIX"ffprobe -hide_banner -v error -select_streams a:0 -show_entries stream=codec_type -of json -i "$INPUT" >>output/vr/tasks/intermediate/probe.txt`
	
	ORIGINALINPUT="$INPUT"
	TARGETPREFIX=${INPUT##*/}
	TARGETPREFIX=output/vr/tasks/intermediate/${TARGETPREFIX%.*}
	TARGETPREFIX=`realpath "$TARGETPREFIX"`
	FINALTARGETFOLDER=`realpath "output/vr/tasks/$TASKNAME"`
	mkdir -p $FINALTARGETFOLDER

	uuid=$(openssl rand -hex 16)
	INTERMEDIATE_INPUT_FOLDER=input/vr/tasks/intermediate/$uuid
	mkdir -p $INTERMEDIATE_INPUT_FOLDER
	EXTENSION="${INPUT##*.}"
	IMAGEINTERMEDIATE=$INTERMEDIATE_INPUT_FOLDER/tmp-input.$EXTENSION
	cp -fv $INPUT $IMAGEINTERMEDIATE
	INPUT="$IMAGEINTERMEDIATE"
	INPUT=`realpath "$INPUT"`

	upperlimits=`cat "$BLUEPRINTCONFIG" | grep -o '"upperlimits":[^"]*"[^"]*"' | sed -E 's/".*".*"(.*)"/\1/'`
	for parameterkv in $(echo $upperlimits | sed "s/,/ /g")
	do
		assertlimit "true" "$parameterkv"
	done
	
	lowerlimits=`cat "$BLUEPRINTCONFIG" | grep -o '"lowerlimits":[^"]*"[^"]*"' | sed -E 's/".*".*"(.*)"/\1/'`
	for parameterkv in $(echo $lowerlimits | sed "s/,/ /g")
	do
		assertlimit "false" "$parameterkv"
	done
	
	
	workflow_api=`cat "$BLUEPRINTCONFIG" | grep -o '"workflow_api":[^"]*"[^"]*"' | sed -E 's/".*".*"(.*)"/\1/'`

	prompt=`cat "$BLUEPRINTCONFIG" | grep -o '"prompt":[^"]*"[^"]*"' | sed -E 's/".*".*"(.*)"/\1/'`
	
	[ $loglevel -lt 2 ] && set -x
	"$PYTHON_BIN_PATH"python.exe $SCRIPTPATH "$workflow_api" "$INPUT" "$TARGETPREFIX" "$prompt"
	set +x && [ $loglevel -ge 2 ] && set -x

	EXTENSION=".mp4"
	
	start=`date +%s`
	end=`date +%s`
	secs=0
	until [ "$queuecount" = "0" ]
	do
		sleep 1
		
		curl -silent "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json
		queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
	
		end=`date +%s`
		secs=$((end-start))
		itertimemsg=`printf '%02d:%02d:%02s\n' $((secs/3600)) $((secs%3600/60)) $((secs%60))`
		echo -ne "$itertimemsg         \r"
	done
	runtime=$((end-start))
	[ $loglevel -ge 0 ] && echo "done. duration: $runtime""s.                             "
	
	INTERMEDIATE=`find output/vr/tasks/intermediate -name "${TARGETPREFIX##*/}"*"$EXTENSION" -print`
  INTERMEDIATECAP=`find output/vr/tasks/intermediate -name "${TARGETPREFIX##*/}"*".txt" -print`
  INTERMEDIATEIMG=`find output/vr/tasks/intermediate -name "${TARGETPREFIX##*/}"*".png" -print`
  if [[ "$TARGETPREFIX" =~ _[0-9]{5}_$ ]]; then
      # Already matches the pattern; do nothing
      :
  else
      TARGETPREFIX="${TARGETPREFIX}_00001_"
  fi  
	FINALTARGET="$FINALTARGETFOLDER/""${TARGETPREFIX##*/}""$EXTENSION"
	FINALTARGETCAP="$FINALTARGETFOLDER/""${TARGETPREFIX##*/}"".txt"
  tmp=${TARGETPREFIX%_}
  num=${tmp##*_}
  prefix=${tmp%_*}_
  TARGETPREFIXNEXT=$(printf "%s%05d_" "$prefix" "$((num+1))")
	FINALTARGETIMG="$FINALTARGETFOLDER/""${TARGETPREFIXNEXT##*/}"".png"

	if [ -s "$INTERMEDIATE" ] && [ -s "$INTERMEDIATEIMG" ] ; then
  	[ -e "$EXIFTOOLBINARY" ] && "$EXIFTOOLBINARY" -m -tagsfromfile "$ORIGINALINPUT" -ItemList:Title -ItemList:Comment -creditLine -xmp:rating -SharedUserRating -overwrite_original "$INTERMEDIATE" && echo "tags copied."
		mv -- "$INTERMEDIATE" "$FINALTARGET"
		mv -- "$INTERMEDIATEIMG" "$FINALTARGETIMG"
		#mv -- "$INTERMEDIATECAP" "$FINALTARGETCAP"
		mkdir -p input/vr/tasks/$TASKNAME/done
		mv -- $ORIGINALINPUT input/vr/tasks/$TASKNAME/done
		rm -f -- "$TARGETPREFIX""$EXTENSION" 2>/dev/null
	  rm -rf -- $INTERMEDIATE_INPUT_FOLDER
		echo -e $"\e[92mtask done.\e[0m"
	else
		echo -e $"\e[91mError:\e[0m Task failed. $INTERMEDIATE missing or zero-length."
		mkdir -p input/vr/tasks/$TASKNAME/error
		mv -- $ORIGINALINPUT input/vr/tasks/$TASKNAME/error
	fi
	

fi
exit 0

