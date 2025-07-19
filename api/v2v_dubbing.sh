#!/bin/sh
#
# v2v_limit4K.sh
#
# Downscales a video (input) to 4K resolution (3840 width). the targetvideo is same path adding _4K to filename.
#
# Copyright (c) 2025 FortunaCournot. MIT License.

# ComfyUI is not used.

# set FFMPEGPATH if ffmpeg binary is not in your enviroment path
FFMPEGPATH=
# either start this script in ComfyUI folder or enter absolute path of ComfyUI folder in your ComfyUI_windows_portable here
COMFYUIPATH=.
# API relative to COMFYUIPATH, or absolute path:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/v2v_dubbing.py

if test $# -ne 1
then
    echo "Usage: $0 input"
    echo "E.g.: $0 SmallIconicTown_SBS_LR.mp4"
else
	echo "Work in progress. Skipping"
	exit

	cd $COMFYUIPATH

	INPUT="$1"
	shift
	
	mkdir -p output/dubbing
	
	PROGRESS=" "
	if [ -e input/dubbing_in/BATCHPROGRESS.TXT ]
	then
		PROGRESS=`cat input/dubbing_in/BATCHPROGRESS.TXT`" "
	fi
	regex="[^/]*$"
	echo "========== $PROGRESS""dubbing "`echo $INPUT | grep -oP "$regex"`" =========="
	
	TARGETPREFIX=${INPUT##*/}
	TARGETPREFIX=output/dubbing/${TARGETPREFIX%.mp4}_dub
	INPUT=`realpath "$INPUT"`
	INPUTPATH=`dirname $INPUT`

	"$PYTHON_BIN_PATH"python.exe $SCRIPTPATH $INPUT $TARGETPREFIX
	
	echo "Waiting for queue to finish..."
	sleep 4  # Give some extra time to start...
	lastcount=""
	start=`date +%s`
	startjob=$start
	itertimemsg=""
	until [ "$queuecount" = "0" ]
	do
		sleep 1
		curl -silent "http://127.0.0.1:8188/prompt" >queuecheck.json
		queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
		if [[ "$lastcount" != "$queuecount" ]] && [[ -n "$lastcount" ]]
		then
			end=`date +%s`
			runtime=$((end-start))
			start=`date +%s`
			secs=$(("$queuecount * runtime"))
			eta=`printf '%02d:%02d:%02s\n' $((secs/3600)) $((secs%3600/60)) $((secs%60))`
			itertimemsg=", $runtime""s/prompt, ETA: $eta"
		fi
		lastcount="$queuecount"
			
		echo -ne "queuecount: $queuecount $itertimemsg         \r"
	done
	runtime=$((end-startjob))
	echo "done. duration: $runtime""s.                      "
	rm queuecheck.json

	mkdir -p input/dubbing_in/done
	if [ -e "$TARGETPREFIX"".mp4" ]
	then
		mv "$INPUT" input/dubbing_in/done
		mv "$TARGETPREFIX"".mp4" input/upscale_in
	else
		echo "Error: Result not found: $TARGETPREFIX"".mp4"
	fi
fi

