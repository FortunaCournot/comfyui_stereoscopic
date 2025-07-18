#!/bin/sh
#
# i2i_sbs_converter.sh
#
# Creates SBS image from a base image (input) and places result under ComfyUI/output/sbs folder.
# The end condition must be checked manually in ComfyUI Frontend (Browser). If queue is empty the concat script (path is logged) can be called. 
#
# Copyright (c) 2025 FortunaCournot. MIT License.

# ComfyUI API script needs the following custom node packages: 
#  comfyui_stereoscopic, comfyui_controlnet_aux, comfyui-videohelpersuite, bjornulf_custom_nodes, comfyui-easy-use, comfyui-custom-scripts, ComfyLiterals

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).
# Prerequisite: Configured path variables below.
# Prerequisite: Git Bash installed. Call this script in Git Bash

# - It will split the input video into segements,
# - It queues sbs conversion workflows via api,
# - Creates a shell script for concating resulting sbs segments
# - Wait until comfyui is done, then call created script manually.


# set FFMPEGPATH if ffmpeg binary is not in your enviroment path
FFMPEGPATH=
# either start this script in ComfyUI folder or enter absolute path of ComfyUI folder in your ComfyUI_windows_portable here
COMFYUIPATH=.
# API relative to COMFYUIPATH, or absolute path:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/i2i_sbs_converter.py
# Use Systempath for python by default, but set it explictly for comfyui portable.
PYTHON_BIN_PATH=
if [ -d "../python_embeded" ]; then
  PYTHON_BIN_PATH=../python_embeded/
fi

if test $# -ne 3
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 depth_scale depth_offset input"
    echo "E.g.: $0 1.0 0.0 SmallIconicTown.mp4"
else

	cd $COMFYUIPATH

	depth_scale="$1"
	shift
	depth_offset="$1"
	shift
	INPUT="$1"
	shift

	PROGRESS=" "
	if [ -e input/sbs_in/BATCHPROGRESS.TXT ]
	then
		PROGRESS=`cat input/sbs_in/BATCHPROGRESS.TXT`" "
	fi
	regex="[^/]*$"
	echo "========== $PROGRESS""convert "`echo $INPUT | grep -oP "$regex"`" =========="

	if test `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $INPUT` -lt 128 -o `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $INPUT` -lt  128
	then
		echo "Skipping low resolution image: $INPUT"
	else
		SCALINGINTERMEDIATE=
		TARGETPREFIX=${INPUT##*/}

		if test `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $INPUT` -gt  8688
		then
			SCALINGINTERMEDIATE=tmpscalingH.png
			echo "downscaling width ..."
			nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y  -i "$INPUT" -vf scale=3840:-1 "$SCALINGINTERMEDIATE"
			mv "$INPUT" input/sbs_in/done
			INPUT="$SCALINGINTERMEDIATE"
		fi

		if test `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $INPUT` -gt  8688
		then
			SCALINGINTERMEDIATE=tmpscalingV.png
			echo "downscaling height ..."
			nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y  -i "$INPUT" -vf scale=-1:3840 "$SCALINGINTERMEDIATE"
			if [ -z "$SCALINGINTERMEDIATE" ]; then
				mv "$INPUT" input/sbs_in/done
			else
				rm "$INPUT"
			fi
			INPUT="$SCALINGINTERMEDIATE"
		fi
	
		INPUT=`realpath "$INPUT"`
		TARGETPREFIX=output/fullsbs/${TARGETPREFIX%.*}
		TARGETPREFIX="$TARGETPREFIX""_SBS_LR"
		TARGETPREFIX=`realpath "$TARGETPREFIX"`
		echo "Converting SBS from $INPUT"
		if [ -e "$INPUT" ]
		then
			echo "Generating to $TARGETPREFIX ..."
			"$PYTHON_BIN_PATH"python.exe $SCRIPTPATH $depth_scale $depth_offset "$INPUT" "$TARGETPREFIX"
			INTERMEDIATE="$TARGETPREFIX""_00001_.png"
			rm -f "$TARGETPREFIX""*.png"
			mkdir -p input/sbs_in/done

			start=`date +%s`
			end=`date +%s`
			secs=0
			until [ -e "$INTERMEDIATE" ]
			do
				sleep 1
				end=`date +%s`
				secs=$((end-start))
				itertimemsg=`printf '%02d:%02d:%02s\n' $((secs/3600)) $((secs%3600/60)) $((secs%60))`
				echo -ne "$itertimemsg         \r"
			done
			
			FINALTARGET="${INTERMEDIATE%_00001_.png}"".png"
			echo "Moving to $FINALTARGET"
			mv "$INTERMEDIATE" "$FINALTARGET"
			if [ -z "$SCALINGINTERMEDIATE" ]; then
				mv "$INPUT" input/sbs_in/done
			else
				rm "$INPUT"
			fi
			echo "done in $secs""s.                      "
		else
			echo "Input file not found: $INPUT"
		fi
	fi
fi

