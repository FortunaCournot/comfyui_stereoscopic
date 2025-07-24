#!/bin/sh
#
# i2i_upscale_downscale.sh
#
# Upscales a base video (input) by 4x_foolhardy_Remacri , then downscales it to fit 4K and places result (png) under ComfyUI/output subfolder.
#
# Copyright (c) 2025 FortunaCournot. MIT License.

# ComfyUI API script needs the following custom node packages: 
#  comfyui-videohelpersuite, bjornulf_custom_nodes, comfyui-easy-use, comfyui-custom-scripts, ComfyLiterals

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).
# Prerequisite: Configured path variables below.
# Prerequisite: Git Bash installed. Call this script in Git Bash

# - It will split the input video into segements,
# - It queues upscale conversion workflows via api,
# - Creates a shell script for concating resulting sbs segments
# - Wait until comfyui is done, then call created script manually.

# set FFMPEGPATH if ffmpeg binary is not in your enviroment path
FFMPEGPATH=
# either start this script in ComfyUI folder or enter absolute path of ComfyUI folder in your ComfyUI_windows_portable here
COMFYUIPATH=.
# API relative to COMFYUIPATH, or absolute path:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/i2i_upscale_downscale.py


if test $# -ne 1 -a $# -ne 2
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 input [upscalefactor]"
    echo "E.g.: $0 SmallIconicTown.png 2"
elif [ -e "$COMFYUIPATH/models/upscale_models/4x_foolhardy_Remacri.pth" ]
then
	cd $COMFYUIPATH

	# Use Systempath for python by default, but set it explictly for comfyui portable.
	PYTHON_BIN_PATH=
	if [ -d "../python_embeded" ]; then
	  PYTHON_BIN_PATH=../python_embeded/
	fi

	DOWNSCALE=1.0
	INPUT="$1"
	shift
	
	UPSCALEFACTOR=0
	if test $# -eq 1
	then
		UPSCALEFACTOR="$1"
		if [ "$UPSCALEFACTOR" -eq 4 ]
		then
			TARGETPREFIX="$TARGETPREFIX""_x4"
			DOWNSCALE=1.0
		elif [ "$UPSCALEFACTOR" -eq 2 ]
		then
			TARGETPREFIX="$TARGETPREFIX""_x2"
			DOWNSCALE=0.5
		else
			 echo "Error: Allowed upscalefactor values: 2 or 4"
			exit
		fi
	fi
	
	PROGRESS=" "
	if [ -e input/upscale_in/BATCHPROGRESS.TXT ]
	then
		PROGRESS=`cat input/upscale_in/BATCHPROGRESS.TXT`" "
	fi
	regex="[^/]*$"
	echo "========== $PROGRESS""rescale "`echo $INPUT | grep -oP "$regex"`" =========="
	
	TARGETPREFIX=${INPUT##*/}
	EXTENSION="${TARGETPREFIX##*.}"
	INPUT=`realpath "$INPUT"`
	TARGETPREFIX=${TARGETPREFIX%.*}
	FINALTARGETFOLDER=`realpath "output/upscale"`
	UPSCALEMODEL="4x_foolhardy_Remacri.pth"
	if [ "$UPSCALEFACTOR" -eq 0 ]
	then
		if test `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $INPUT` -le 1920 -a `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $INPUT` -le  1080
		then 
			if test `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $INPUT` -le 960 -a `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $INPUT` -le  540
			then 
				TARGETPREFIX="$TARGETPREFIX""_x4"
				DOWNSCALE=1.0
				UPSCALEFACTOR=4
			else
				TARGETPREFIX="$TARGETPREFIX""_x2"
				DOWNSCALE=0.5
				UPSCALEFACTOR=2
			fi
		fi
	fi
	
	if [ "$UPSCALEFACTOR" -gt 0 ]
	then

		echo "prompting for $TARGETPREFIX"

	
		echo -ne "Prompting ..."
		rm -f output/upscale/tmpscaleresult*.png
		"$PYTHON_BIN_PATH"python.exe $SCRIPTPATH "$INPUT" upscale/tmpscaleresult $UPSCALEMODEL $DOWNSCALE
		
		echo -ne "Waiting for queue to finish..."
		sleep 2  # Give some extra time to start...
		lastcount=""
		start=`date +%s`
		end=`date +%s`
		startjob=$start
		itertimemsg=""
		queuecount=
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
				itertimemsg=", $runtime""s/prompt, ETA in $eta"
			fi
			lastcount="$queuecount"
			
			#echo -ne "queuecount: $queuecount $itertimemsg         \r"
		done
		runtime=$((end-startjob))
		echo "done."
		rm queuecheck.json

		sleep 1
		if [ -e "output/upscale/tmpscaleresult_00001_.png" ]
		then
			mv -f output/upscale/tmpscaleresult_00001_.png "$FINALTARGETFOLDER"/"$TARGETPREFIX"".png"
		else	
			echo " "
			echo "Error: Failed to upscale. File output/upscale/tmpscaleresult_00001_.png not found "
		fi

	else
		echo "Skipping upscaling of image $INPUT. Moving to $FINALTARGETFOLDER"
		cp -f $INPUT "$FINALTARGETFOLDER"
	fi
else
	if [ ! -e "$COMFYUIPATH/models/upscale_models/4x_foolhardy_Remacri.pth" ]
	then
		echo "Warning: Upscale model not installed. use the Manager to install 4x_foolhardy_Remacri to $COMFYUIPATH/models/upscale_models/4x_foolhardy_Remacri.pth"
	fi
fi

