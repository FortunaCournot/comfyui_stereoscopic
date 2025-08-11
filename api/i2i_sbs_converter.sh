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


# either start this script in ComfyUI folder or enter absolute path of ComfyUI folder in your ComfyUI_windows_portable here
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=$(dirname "$0")/../../..
# API relative to COMFYUIPATH, or absolute path:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/python/i2i_sbs_converter.py
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

	# set FFMPEGPATHPREFIX if ffmpeg binary is not in your enviroment path
	FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}
	
	EXIFTOOLBINARY=$(awk -F "=" '/EXIFTOOLBINARY/ {print $2}' $CONFIGFILE) ; EXIFTOOLBINARY=${EXIFTOOLBINARY:-""}

	depth_scale="$1"
	shift
	depth_offset="$1"
	shift
	INPUT="$1"
	shift
						   
	DEPTH_MODEL_CKPT=$(awk -F "=" '/DEPTH_MODEL_CKPT/ {print $2}' $CONFIGFILE) ; DEPTH_MODEL_CKPT=${DEPTH_MODEL_CKPT:-"depth_anything_v2_vitl.pth"}

	PROGRESS=" "
	if [ -e input/vr/fullsbs/BATCHPROGRESS.TXT ]
	then
		PROGRESS=`cat input/vr/fullsbs/BATCHPROGRESS.TXT`" "
	fi
	regex="[^/]*$"
	echo "========== $PROGRESS""convert sbs "`echo $INPUT | grep -oP "$regex"`" =========="


	ORIGINALINPUT="$INPUT"
	TARGETPREFIX=${INPUT##*/}
	TARGETPREFIX=output/vr/fullsbs/${TARGETPREFIX%.*}
	TARGETPREFIX="$TARGETPREFIX""_SBS_LR"
	TARGETPREFIX=`realpath "$TARGETPREFIX"`

	uuid=$(openssl rand -hex 16)
	INTERMEDIATE_INPUT_FOLDER=input/vr/fullsbs/intermediate/$uuid
	mkdir -p $INTERMEDIATE_INPUT_FOLDER
	EXTENSION="${INPUT##*.}"
	SCALINGINTERMEDIATE=$INTERMEDIATE_INPUT_FOLDER/tmp-sbsinput.$EXTENSION
	cp -fv $INPUT $SCALINGINTERMEDIATE
	INPUT="$SCALINGINTERMEDIATE"

	if [[ "$EXTENSION" == "webm" ]] || [[ "$EXTENSION" == "WEBM" ]] ; then
		echo "handling unsupported image format"
		SCALINGINTERMEDIATE=$INTERMEDIATE_INPUT_FOLDER/tmpscalingEXT.png
		nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y  -i "$INPUT" "$SCALINGINTERMEDIATE"
		INPUT="$SCALINGINTERMEDIATE"
	fi
	
	if test `"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $INPUT` -lt 128 -o `"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $INPUT` -lt  128
	then
		echo -e $"\e[91mError:\e[0m Skipping low resolution image: $INPUT"
		mkdir -p  input/vr/fullsbs/error
		mv -fv $INPUT input/vr/fullsbs/error
	else

		if test `"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $INPUT` -gt  8688
		then
			SCALINGINTERMEDIATE=$INTERMEDIATE_INPUT_FOLDER/tmpscalingH.png
			echo "downscaling width ..."
			nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y  -i "$INPUT" -vf scale=3840:-1 "$SCALINGINTERMEDIATE"
			mv "$INPUT" input/vr/fullsbs/done
			INPUT="$SCALINGINTERMEDIATE"
		fi

		if test `"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $INPUT` -gt  8688
		then
			SCALINGINTERMEDIATE=$INTERMEDIATE_INPUT_FOLDER/tmpscalingV.png
			echo "downscaling height ..."
			nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y  -i "$INPUT" -vf scale=-1:3840 "$SCALINGINTERMEDIATE"
			if [ -z "$SCALINGINTERMEDIATE" ]; then
				mv "$INPUT" input/vr/fullsbs/done
			else
				rm "$INPUT"
			fi
			INPUT="$SCALINGINTERMEDIATE"
		fi
	
		
		INPUT=`realpath "$INPUT"`
		queuecount=
		echo "Converting SBS from $INPUT"
		if [ -e "$INPUT" ]
		then
			echo "Generating to $TARGETPREFIX ..."

			# rm -f -- "$TARGETPREFIX"*.png 2>/dev/null
			
			echo -ne $"\e[91m" ; "$PYTHON_BIN_PATH"python.exe $SCRIPTPATH "$DEPTH_MODEL_CKPT" $depth_scale $depth_offset "$INPUT" "$TARGETPREFIX" ; echo -ne $"\e[0m"
			INTERMEDIATE="$TARGETPREFIX""_00001_.png"
			rm -f $TARGETPREFIX*.png
			mkdir -p input/vr/fullsbs/done

			start=`date +%s`
			end=`date +%s`
			secs=0
			until [ -e "$INTERMEDIATE" ] || [ "$queuecount" = "0" ]
			do
				sleep 1
				
				status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
				if test $# -ne 0
				then	
					echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
					exit
				fi
				curl -silent "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json
				queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
			
				end=`date +%s`
				secs=$((end-start))
				itertimemsg=`printf '%02d:%02d:%02s\n' $((secs/3600)) $((secs%3600/60)) $((secs%60))`
				echo -ne "$itertimemsg         \r"
			done
			runtime=$((end-start))
			[ $loglevel -ge 0 ] && echo "done. duration: $runtime""s.                             "
			
			TARGETPREFIX=${TARGETPREFIX##*/}
			FINALTARGET="output/vr/fullsbs/""$TARGETPREFIX"".png"
			echo "Moving to $FINALTARGET"
			sync
			sleep 1 # Device or resource busy
			if [ -e "$INTERMEDIATE" ]; then
				while [ -e "$INTERMEDIATE" ]; do
					sleep 1
					[ -e "$EXIFTOOLBINARY" ] && "$EXIFTOOLBINARY" -all= -tagsfromfile "$ORIGINALINPUT" -all:all -overwrite_original "$INTERMEDIATE" && echo "tags copied."
					[ -e "$EXIFTOOLBINARY" ] && "$EXIFTOOLBINARY" -m '-iptc:credit<\$iptc:credit''. VR we are - https://civitai.com/models/1757677 .' -overwrite_original "$INTERMEDIATE" 
					mv -fv "$INTERMEDIATE" "$FINALTARGET"
					if [ -e "$FINALTARGET" ]; then
						if [ -e "$INPUT" ]; then
							mkdir -p input/vr/fullsbs/done
							mv -fv "$ORIGINALINPUT" input/vr/fullsbs/done
						else
							echo -e $"\e[93mWarning:\e[0m Input file to cleanup not found: $INPUT"
						fi
						echo -e $"\e[92mdone\e[0m in $secs""s.                      "
					fi
				done
			else
				echo -e $"\e[91mError:\e[0m Result file not found: $INTERMEDIATE"
				ls -l "$TARGETPREFIX"*
				mkdir -p input/vr/fullsbs/error
				mv -fv "$ORIGINALINPUT" input/vr/fullsbs/error
			fi
		else
			echo -e $"\e[91mError:\e[0m Input file not found: $INPUT"
		fi
	fi
	rm -rf $INTERMEDIATE_INPUT_FOLDER
fi

