#!/bin/sh
#
# v2v_sbs_converter.sh || exit 1
#
# Creates SBS video from a base video (input) and places result under ComfyUI/output/sbs folder.
#
# Copyright (c) 2025 Fortuna Cournot. MIT License. www.3d-gallery.org

# This script depends on the CLI version of the SBS converter from Iablunoshka (https://github.com/Iablunoshka)

# Prerequisite: Configured path variables below.
# Prerequisite: Git Bash installed. Call this script in Git Bash



# either start this script in ComfyUI folder or enter absolute path of ComfyUI folder in your ComfyUI_windows_portable here
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# API relative to COMFYUIPATH, or absolute path:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/cli/sbs/main.py
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
	
	# set FFMPEGPATHPREFIX if ffmpeg binary is not in your enviroment path
	FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX=/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}

	depth_scale="$1"
	shift
	depth_offset="$1"
	shift
	INPUT="$1"
	if [ ! -e "$1" ] ; then echo "input file removed: $INPUT"; exit 0; fi
	shift

	blur_radius=$(awk -F "=" '/SBS_DEPTH_BLUR_RADIUS_VIDEO=/ {print $2}' $CONFIGFILE) ; SBS_DEPTH_BLUR_RADIUS_VIDEO=${SBS_DEPTH_BLUR_RADIUS_VIDEO:-"19"}

	DEPTH_MODEL_CKPT=$(awk -F "=" '/DEPTH_MODEL_CKPT=/ {print $2}' $CONFIGFILE) ; DEPTH_MODEL_CKPT=${DEPTH_MODEL_CKPT:-"depth_anything_v2_vits.pth"}
	
	DEPTH_RESOLUTION=$(awk -F "=" '/DEPTH_RESOLUTION=/ {print $2}' $CONFIGFILE) ; DEPTH_RESOLUTION=${DEPTH_RESOLUTION:-"256"}
	
	VIDEO_FORMAT=$(awk -F "=" '/VIDEO_FORMAT=/ {print $2}' $CONFIGFILE) ; VIDEO_FORMAT=${VIDEO_FORMAT:-"video/h264-mp4"}
	VIDEO_PIXFMT=$(awk -F "=" '/VIDEO_PIXFMT=/ {print $2}' $CONFIGFILE) ; VIDEO_PIXFMT=${VIDEO_PIXFMT:-"yuv420p"}
	VIDEO_CRF=$(awk -F "=" '/VIDEO_CRF=/ {print $2}' $CONFIGFILE) ; VIDEO_CRF=${VIDEO_CRF:-"17"}

	CWD=`pwd`
	CWD=`realpath "$CWD"`
	
	# some advertising ;-)
	SETMETADATA="-metadata description=\"Created with Side-By-Side Converter: https://civitai.com/models/1757677\" -movflags +use_metadata_tags -metadata depth_scale=\"$depth_scale\" -metadata depth_offset=\"$depth_offset\""

	PROGRESS=" "
	if [ -e input/vr/fullsbs/BATCHPROGRESS.TXT ]
	then
		PROGRESS=`cat input/vr/fullsbs/BATCHPROGRESS.TXT`" "
	fi
	regex="[^/]*$"
	echo "========== $PROGRESS""convert sbs "`echo $INPUT | grep -oP "$regex"`" =========="

	uuid=$(openssl rand -hex 16)
	TARGETPREFIX=${INPUT##*/}
	INPUT=`realpath "$INPUT"`
	TARGETPREFIX_SBS=${TARGETPREFIX%.*}"_SBS_LR"
	INTERMEDIATEPREFIX=output/vr/fullsbs/intermediate/$TARGETPREFIX_SBS-$uuid
	INPUTPREFIX=input/vr/fullsbs/intermediate/$TARGETPREFIX_SBS
	FINALTARGETFOLDER=`realpath "output/vr/fullsbs"`
	
	INPUT2="$INPUT"
	RESW=`"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $INPUT2`
	if [ $RESW -gt 1920 ] ; then
		nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -stats -y -i "$INPUT2" -filter:v "scale=1920:-2" "$INTERMEDIATEPREFIX""-d"".mp4" 
		INPUT2="$INTERMEDIATEPREFIX""-d"".mp4"
	fi
	RESH=`"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $INPUT2`
	if [ $RESH -gt 2160 ] ; then
		nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -stats -y -i "$INPUT2" -filter:v "scale=-2:2160" "$INTERMEDIATEPREFIX""-d"".mp4" 
		INPUT2="$INTERMEDIATEPREFIX""-d"".mp4"
	fi
	
	lastcount=""
	start=`date +%s`
	end=`date +%s`
	startjob=$start
	itertimemsg=""

	mkdir -p output/vr/fullsbs/intermediate
	
	#"$DEPTH_MODEL_CKPT" $DEPTH_RESOLUTION $depth_scale $depth_offset $blur_radius "$f"
	#--preset balance
	"$PYTHON_BIN_PATH"python.exe $SCRIPTPATH -i "$INPUT2" -o "$INTERMEDIATEPREFIX"".mp4" -model_name "depth-anything/Depth-Anything-V2-Small-hf" -depth_scale $depth_scale -depth_offset $depth_offset -blur_radius $blur_radius 
	mv "$INTERMEDIATEPREFIX"".mp4" "$FINALTARGETFOLDER"/"$TARGETPREFIX"".mp4"
	end=`date +%s`
	
	if [ ! -s "$FINALTARGETFOLDER"/"$TARGETPREFIX"".mp4" ] ; then
		echo -e $"\e[91mError\e[0m: Converter failed."
		mkdir -p $CWD/input/vr/fullsbs/error
		mv -fv -- $INPUT $CWD/input/vr/fullsbs/error
		exit -1
	fi

	mv -fv -- $INPUT $CWD/input/vr/fullsbs/done
	rm -f -- "$INPUT2" >/dev/null
	runtime=$((end-startjob))
	echo -e $"\e[92mdone.\e[0m duration: $runtime""s.                         "

	
fi
exit 0

