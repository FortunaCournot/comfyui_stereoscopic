#!/bin/sh
#
# i2i_upscale_downscale.sh || exit 1
#
# Upscales a base video (input) by 4x_foolhardy_Remacri , then downscales it to fit 4K and places result (png) under ComfyUI/output subfolder.
#
# Copyright (c) 2025 Fortuna Cournot. MIT License. www.3d-gallery.org

# ComfyUI API script needs the following custom node packages: 
#  comfyui-videohelpersuite, bjornulf_custom_nodes, comfyui-easy-use, comfyui-custom-scripts, ComfyLiterals

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).
# Prerequisite: Configured path variables below.
# Prerequisite: Git Bash installed. Call this script in Git Bash

# - It will split the input video into segements,
# - It queues upscale conversion workflows via api,
# - Creates a shell script for concating resulting sbs segments
# - Wait until comfyui is done, then call created script manually.

# either start this script in ComfyUI folder or enter absolute path of ComfyUI folder in your ComfyUI_windows_portable here
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# API relative to COMFYUIPATH, or absolute path:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/python/i2i_upscale_downscale.py


if test $# -ne 2 -a $# -ne 3
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 input override_active [upscalefactor]"
    echo "E.g.: $0 SmallIconicTown.png 2"
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

	# set FFMPEGPATHPREFIX if ffmpeg binary is not in your enviroment path
	FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX=/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}

	EXIFTOOLBINARY=$(awk -F "=" '/EXIFTOOLBINARY=/ {print $2}' $CONFIGFILE) ; EXIFTOOLBINARY=${EXIFTOOLBINARY:-""}

	# Use Systempath for python by default, but set it explictly for comfyui portable.
	PYTHON_BIN_PATH=
	if [ -d "../python_embeded" ]; then
	  PYTHON_BIN_PATH=../python_embeded/
	fi

	DOWNSCALE=1.0
	INPUT="$1"

	if [ ! -e "$INPUT" ] ; then echo "input file removed: $INPUT"; exit 0; fi
	shift
	override_active=$1
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
			 echo -e $"\e[91mError:\e[0m Allowed upscalefactor values: 2 or 4"
			exit 1
		fi
	fi
	
	PROGRESS=" "
	if [ -e input/vr/scaling/BATCHPROGRESS.TXT ]
	then
		PROGRESS=`cat input/vr/scaling/BATCHPROGRESS.TXT`" "
	fi
	regex="[^/]*$"
	echo "========== $PROGRESS""scaling "`echo $INPUT | grep -oP "$regex"`" =========="

	uuid=$(openssl rand -hex 16)
	INTERMEDIATE_INPUT_FOLDER=input/vr/scaling/intermediate/$uuid
	mkdir -p $INTERMEDIATE_INPUT_FOLDER
	ORIGINALINPUT="$INPUT"
	TARGETPREFIX=${INPUT##*/}
	INPUTFILENAME=$TARGETPREFIX
	EXTENSION="${TARGETPREFIX##*.}"
	INPUT=`realpath "$INPUT"`
	TARGETPREFIX=${TARGETPREFIX%.*}
	FINALTARGETFOLDER=`realpath "output/vr/scaling"`
	UPSCALEMODEL="RealESRGAN_x4plus.pth"
	SCALEBLENDFACTOR=$(awk -F "=" '/SCALEBLENDFACTOR=/ {print $2}' $CONFIGFILE) ; SCALEBLENDFACTOR=${SCALEBLENDFACTOR:-"0.7"}
	SCALESIGMARESOLUTION=$(awk -F "=" '/SCALESIGMARESOLUTION=/ {print $2}' $CONFIGFILE) ; SCALESIGMARESOLUTION=${SCALESIGMARESOLUTION:-"1920.0"}

	RESW=`"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $INPUT`
	RESH=`"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $INPUT`
	PIXEL=$(( $RESW * $RESH ))

	LIMIT4X=518400
	LIMIT2X=2073600
	if [ $override_active -gt 0 ]; then
		[ $loglevel -ge 1 ] && echo "override active"
		LIMIT4X=1036800
		LIMIT2X=4147200
	fi

	if [ "$UPSCALEFACTOR" -eq 0 ]
	then
		if [ $PIXEL -lt $LIMIT2X ]; then
			if [ $PIXEL -lt $LIMIT4X ]; then
				TARGETPREFIX="$TARGETPREFIX""_x4"
				UPSCALEMODEL=$(awk -F "=" '/UPSCALEMODELx4=/ {print $2}' $CONFIGFILE) ; UPSCALEMODEL=${UPSCALEMODEL:-"RealESRGAN_x4plus.pth"}
				DOWNSCALE=1.0
				UPSCALEFACTOR=4
				[ $loglevel -ge 1 ] && echo "using $UPSCALEFACTOR""x"
			else
				TARGETPREFIX="$TARGETPREFIX""_x2"
				UPSCALEMODEL=$(awk -F "=" '/UPSCALEMODELx2=/ {print $2}' $CONFIGFILE) ; UPSCALEMODEL=${UPSCALEMODEL:-"RealESRGAN_x4plus.pth"}
				DOWNSCALE=1.0
				UPSCALEFACTOR=2
				[ $loglevel -ge 1 ] && echo "using $UPSCALEFACTOR""x"
			fi
		else
			[ $loglevel -ge 1 ] && echo "$PIXEL > $LIMIT2X"
		fi
	fi
	
	if [[ "$EXTENSION" == "webm" ]] || [[ "$EXTENSION" == "WEBM" ]] ; then
		echo "handling unsupported image format"
		SCALINGINTERMEDIATE=$INTERMEDIATE_INPUT_FOLDER/tmpscalingEXT.png
		nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y  -i "$INPUT" "$SCALINGINTERMEDIATE"
		INPUT="$SCALINGINTERMEDIATE"
		INPUT=`realpath "$INPUT"`
	else
		SCALINGINTERMEDIATE=$INTERMEDIATE_INPUT_FOLDER/$INPUTFILENAME
		cp "$INPUT" "$SCALINGINTERMEDIATE"
		INPUT="$SCALINGINTERMEDIATE"
		INPUT=`realpath "$INPUT"`
	fi
	
	if [ "$UPSCALEFACTOR" -gt 0 ]
	then

		echo "prompting for $TARGETPREFIX"

	
		echo -ne "Prompting ..."
		rm -f output/vr/scaling/tmpscaleresult*.png
		echo -ne $"\e[91m" ; "$PYTHON_BIN_PATH"python.exe $SCRIPTPATH "$INPUT" vr/scaling/tmpscaleresult $UPSCALEMODEL $DOWNSCALE $SCALEBLENDFACTOR $SCALESIGMARESOLUTION ; echo -ne $"\e[0m"
			
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
			curl -silent "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json
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
			
			#echo -ne $"\e[1mqueuecount:\e[0m $queuecount $itertimemsg         \r"
		done
		runtime=$((end-startjob))
		echo "                                                       "
		rm queuecheck.json

		sleep 1
		if [ -e "output/vr/scaling/tmpscaleresult_00001_.png" ]
		then
			[ -e "$EXIFTOOLBINARY" ] && "$EXIFTOOLBINARY" -all= -tagsfromfile "$ORIGINALINPUT" -all:all -overwrite_original output/vr/scaling/tmpscaleresult_00001_.png && echo "tags copied."
			mv -fv output/vr/scaling/tmpscaleresult_00001_.png "$FINALTARGETFOLDER"/"$TARGETPREFIX""_4K.png"
			#exit 1
			mkdir -p input/vr/scaling/done
			mv -fv $ORIGINALINPUT input/vr/scaling/done
			echo -e $"\e[92mdone\e[0m in $runtime""s. "
		else
			#echo "ERROR"
			#exit 1
			echo " "
			echo -e $"\e[91mError:\e[0m Failed to upscale. File output/vr/scaling/tmpscaleresult_00001_.png not found "
			mkdir -p input/vr/scaling/error
			mv -fv $ORIGINALINPUT input/vr/scaling/error
			exit 0
		fi

	else
		echo "Skipping upscaling of image $INPUT."
		mv -fv $ORIGINALINPUT "$FINALTARGETFOLDER"/"$TARGETPREFIX""_x1.$EXTENSION"
	fi
	
	rm  -rf $INTERMEDIATE_INPUT_FOLDER
fi
exit 0

