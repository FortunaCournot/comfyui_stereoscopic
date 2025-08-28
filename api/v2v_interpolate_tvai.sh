#!/bin/sh
#
# v2v_interpolate_tvai.sh || exit 1
#
# Interpolates a video (input) with Topaz Video AI and places result under ComfyUI/output/vr/interpolate folder.
#
# Copyright (c) 2025 Fortuna Cournot. MIT License. www.3d-gallery.org


# Prerequisite: Topaz Video AI pathes must be configured and login active.
# Prerequisite: Git Bash installed. Call this script in Git Bash

# either start this script in ComfyUI folder or enter absolute path of ComfyUI folder in your ComfyUI_windows_portable here
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# API relative to COMFYUIPATH, or absolute path:
SCRIPTPATH=


if test $# -ne 3
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 multiplicator vram_gb input"
    echo "E.g.: $0 2 16 SmallIconicTown.mp4"
else
	cd $COMFYUIPATH

	CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini
	CONFIGFILE=`realpath $CONFIGFILE`
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

	EXIFTOOLBINARY=$(awk -F "=" '/EXIFTOOLBINARY/ {print $2}' $CONFIGFILE) ; EXIFTOOLBINARY=${EXIFTOOLBINARY:-""}

	# set FFMPEGPATHPREFIX if ffmpeg binary is not in your enviroment path
	FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}

	# Use Systempath for python by default, but set it explictly for comfyui portable.
	PYTHON_BIN_PATH=
	if [ -d "../python_embeded" ]; then
	  PYTHON_BIN_PATH=../python_embeded/
	fi

	multiplicator="$1"
	shift
	VRAM="$1"
	shift
	INPUT="$1"

	if [ ! -e "$INPUT" ] ; then echo "input file removed: $INPUT"; exit 0; fi
	shift
	override_active=$1
	

	TVAI_BIN_DIR=$(awk -F "=" '/TVAI_BIN_DIR/ {print $2}' $CONFIGFILE) ; TVAI_BIN_DIR=${TVAI_BIN_DIR:-""}
	TVAI_MODEL_DATA_DIR=$(awk -F "=" '/TVAI_MODEL_DATA_DIR/ {print $2}' $CONFIGFILE) ; TVAI_MODEL_DATA_DIR=${TVAI_MODEL_DATA_DIR:-""}
	TVAI_MODEL_DIR=$(awk -F "=" '/TVAI_MODEL_DIR/ {print $2}' $CONFIGFILE) ; TVAI_MODEL_DIR=${TVAI_MODEL_DIR:-""}
	TVAI_FILTER_STRING_IP=`grep TVAI_FILTER_STRING_IP= $CONFIGFILE | cut -d'=' -f2-`
	TVAI_FILTER_STRING_IP=${TVAI_FILTER_STRING_IP:-""}
	TVAI_MODELFI=${TVAI_FILTER_STRING_IP#*"model="}
	TVAI_MODELFI=${TVAI_MODELFI%%:*}

	if [ -e "$TVAI_BIN_DIR" ] && [ -e "$TVAI_MODEL_DATA_DIR" ] && [ -e "$TVAI_MODEL_DIR" ] && [ -e "$TVAI_MODEL_DIR"/$TVAI_MODELFI".json" ] ; then
		export TVAI_MODEL_DATA_DIR TVAI_MODEL_DIR
	else
		echo -e $"\e[91mError:\e[0m TVAI settings wrong. Please configure at $CONFIGFILE"":"
		[ ! -e "$TVAI_BIN_DIR" ] && echo -e $"\e[91mError:\e[0m TVAI_BIN_DIR=$TVAI_BIN_DIR"
		[ ! -e "$TVAI_MODEL_DATA_DIR" ] && echo -e $"\e[91mError:\e[0m TVAI_MODEL_DATA_DIR=$TVAI_MODEL_DATA_DIR"
		[ ! -e "$TVAI_MODEL_DIR" ] && echo -e $"\e[91mError:\e[0m TVAI_MODEL_DIR=$TVAI_MODEL_DIR"
		[ ! -e "$TVAI_MODEL_DIR"/$TVAI_MODELFI".json" ] && echo -e $"\e[91mError:\e[0m TVAI_FILTER_STRING_IP=$TVAI_FILTER_STRING_IP"
		[ ! -e "$TVAI_MODEL_DIR"/$TVAI_MODELFI".json" ] && echo -e $"\e[91m      \e[0m ""$TVAI_MODEL_DIR""/""$TVAI_MODELFI"".json not found in $TVAI_MODEL_DATA_DIR"
		exit 1
	fi
	
	PROGRESS=" "
	if [ -e input/vr/interpolate/BATCHPROGRESS.TXT ]
	then
		PROGRESS=`cat input/vr/interpolate/BATCHPROGRESS.TXT`" "
	fi
	regex="[^/]*$"
	[ $loglevel -ge 0 ] && echo "========== $PROGRESS""interpolate (tvai) "`echo $INPUT | grep -oP "$regex"`" =========="
	
	TARGETPREFIX=${INPUT##*/}
	INPUT=`realpath "$INPUT"`
	TARGETPREFIX_FPS=${TARGETPREFIX%.*}
	TARGETPREFIX=output/vr/interpolate/intermediate/$TARGETPREFIX_FPS
	FINALTARGETFOLDER=`realpath "output/vr/interpolate"`
	mkdir -p output/vr/interpolate/intermediate
	
	VIDEO_PIXFMT=$(awk -F "=" '/VIDEO_PIXFMT/ {print $2}' $CONFIGFILE) ; VIDEO_PIXFMT=${VIDEO_PIXFMT:-"yuv420p"}
	VIDEO_CRF=$(awk -F "=" '/VIDEO_CRF/ {print $2}' $CONFIGFILE) ; VIDEO_CRF=${VIDEO_CRF:-"17"}
	
	`"$FFMPEGPATHPREFIX"ffprobe -hide_banner -v error -select_streams v:0 -show_entries stream=codec_type,codec_name,bit_rate,width,height,r_frame_rate,duration,nb_frames -of json -i "$INPUT" >output/vr/interpolate/intermediate/probe.txt`
	
	temp=`grep width output/vr/interpolate/intermediate/probe.txt`
	temp=${temp#*:}
	temp="${temp%\"*}"
    temp="${temp#*\"}"
    RESW="${temp%,*}"
	
	temp=`grep height output/vr/interpolate/intermediate/probe.txt`
	temp=${temp#*:}
	temp="${temp%\"*}"
    temp="${temp#*\"}"
    RESH="${temp%,*}"

	temp=`grep r_frame_rate output/vr/interpolate/intermediate/probe.txt`
	temp=${temp#*:}
	temp="${temp%\"*}"
    temp="${temp#*\"}"
    temp="${temp%,*}"
	FPS=$(( temp ))
	TARGETFPS=$(( multiplicator * $FPS ))
	
	if [ `echo $RESW | wc -l` -ne 1 ] || [ `echo $RESH | wc -l` -ne 1 ] ; then
		echo -e $"\e[91mError:\e[0m Can't process video. please resample ${INPUT##*/} from input/vr/interpolate/error"
		mkdir -p input/vr/interpolate/error
		mv -f --  $INPUT input/vr/interpolate/error
		exit 0
	fi
	PIXEL=$(( $RESW * $RESH ))
	TVAI_FILTER_STRING_IP="$TVAI_FILTER_STRING_IP""$TARGETFPS"

	JOBLIST="$INPUT"
	if [[ $INPUT == *"_SBS_LR"* ]] ; then
		echo "Splitting..."
		JOBLIST=
		nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -v quiet -stats -y -i "$INPUT" -filter_complex "[0]crop=iw/2:ih:0:0[left];[0]crop=iw/2:ih:ow:0[right]" -map "[left]" "$TARGETPREFIX""-left-input.mp4" -map "[right]" "$TARGETPREFIX""-right-input.mp4"
		
		if [ ! -e "$TARGETPREFIX""-right-input.mp4" ] || [ ! -e "$TARGETPREFIX""-left-input.mp4" ] ; then
				echo -e $"\e[91mError:\e[0m split failed. Check for error messages."
				mkdir -p input/vr/interpolate/error
				mv -vf -- "$INPUT" input/vr/interpolate/error
				exit 0
		fi
		
		JOBLIST=`find output/vr/interpolate/intermediate -maxdepth 1 -type f -name "$TARGETPREFIX_FPS""*-input.mp4"`
	fi
	
	declare -i INDEX=0
	for inputfile in $JOBLIST ; do
		INDEX+=1
		echo "--- $INDEX $inputfile"
		set -x
		nice "$TVAI_BIN_DIR"/ffmpeg.exe -hide_banner -stats  -nostdin -y -strict 2 -hwaccel auto -i "$inputfile" -c:v libvpx-vp9 -g 300 -crf 19 -b:v 2000k -c:a aac -pix_fmt yuv420p -movflags frag_keyframe+empty_moov -filter_complex "$TVAI_FILTER_STRING_IP" "$TARGETPREFIX""-part""$INDEX"".mkv"
		set +x
		if [ ! -e "$TARGETPREFIX""-part""$INDEX".mkv ] ; then
			echo -e $"\e[91mError:\e[0m TVAI generation failed. Please check TVAI_FILTER_STRING_IP in $CONFIGFILE"
			mkdir -p input/vr/interpolate/error
			mv -fv -- "$INPUT" input/vr/interpolate/error
			exit 0
		fi
		
		set -x
		nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -v quiet -stats -y -i "$TARGETPREFIX""-part""$INDEX"".mkv" -c:v libx264 -crf 19 -c:a aac -pix_fmt yuv420p -movflags frag_keyframe+empty_moov "$TARGETPREFIX""-part""$INDEX"".mp4"
		set +x
		if [ ! -e "$TARGETPREFIX"-part"$INDEX".mp4 ] ; then
			echo -e $"\e[91mError:\e[0m TVAI generation failed. Check for error messages."
			mkdir -p input/vr/interpolate/error
			mv -vf -- "$INPUT" input/vr/interpolate/error
			exit 0
		fi
		rm -f -- "$TARGETPREFIX""-part""$INDEX"".mkv"
		
	done

	if [[ $INPUT == *"_SBS_LR"* ]] ; then
		echo "Joining..."

		rm -f -- "$TARGETPREFIX""-right-input.mp4" "$TARGETPREFIX""-left-input.mp4"


		TESTAUDIO=`"$FFMPEGPATHPREFIX"ffprobe -i "$INPUT" -show_streams -select_streams a -loglevel error | head -n 1`
		if [[ $TESTAUDIO =~ "[STREAM]" ]]; then
			set -x
			nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -v quiet -stats -y -i "$TARGETPREFIX""-part1.mp4" -i "$TARGETPREFIX""-part2.mp4" -i "$INPUT" -filter_complex "[0:v][1:v]hstack=inputs=2[v]" -map "[v]" -map "2:a" "$TARGETPREFIX".mp4
			set +x
		else
			set -x
			nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -v quiet -stats -y -i "$TARGETPREFIX""-part1.mp4" -i "$TARGETPREFIX""-part2.mp4" -i "$INPUT" -filter_complex "[0:v][1:v]hstack=inputs=2[v]" -map "[v]" "$TARGETPREFIX".mp4
			set +x
		fi
		if [ ! -e "$TARGETPREFIX".mp4 ] ; then
			echo -e $"\e[91mError:\e[0m join failed. Check for error messages."
			mkdir -p input/vr/interpolate/error
			mv -vf -- "$INPUT" input/vr/interpolate/error
			exit 0
		fi

		rm -f -- "$TARGETPREFIX""-part1.mp4""$TARGETPREFIX""-part2.mp4"

	else
		mv -f -- "$TARGETPREFIX""-part1.mp4" "$TARGETPREFIX".mp4
	fi

	mv "$TARGETPREFIX"".mp4" $FINALTARGETFOLDER
	mkdir -p input/vr/interpolate/done
	mv -f -- "$INPUT" input/vr/interpolate/done
	echo -e $"\e[92mdone\e[0m"
	
fi
exit 0

