#!/bin/sh
#
# batch_downscale.sh
#
# downscale a video (input).
#
# Copyright (c) 2025 FortunaCournot. MIT License.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable. ComfyUI server is not used.
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# relative to COMFYUIPATH:

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

	TARGETSIZE="4K"

	mkdir -p output/vr/downscale/$TARGETSIZE
	mkdir -p output/vr/downscale/$TARGETSIZE/intermediate
	mkdir -p input/vr/downscale/$TARGETSIZE/done
	
	COUNT=`find input/vr/downscale/$TARGETSIZE -maxdepth 1 -type f -name '*.mp4' | wc -l`
	declare -i INDEX=0
	if [[ $COUNT -gt 0 ]] ; then
	
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "****** DOWNSCALING *******"
		[ $loglevel -ge 1 ] && echo "**************************"
	
		for nextinputfile in input/vr/downscale/$TARGETSIZE/*.mp4 ; do
			INDEX+=1
			newfn=${nextinputfile##*/}
			newfn=input/vr/downscale/${newfn//[^[:alnum:].]/_}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			newfn=$newfn
			mv "$nextinputfile" $newfn 
			
			regex="[^/]*$"
			echo "$INDEX/$COUNT: downscale "`echo $newfn | grep -oP "$regex"`
			
			if [ -e "$newfn" ]
			then
				WIDTH=`"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $newfn`
				HEIGHT=`"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $newfn`
				
				TARGETDIM=3840
				
				if [ $WIDTH -ge $HEIGHT ] ; then
					TARGETSCALEOPT=scale=$TARGETDIM:-2
				else
					TARGETSCALEOPT=scale=-2:$TARGETDIM
				fi
				
				TARGETPREFIX=${newfn##*/}
				TARGETPREFIX=${TARGETPREFIX%.mp4}
				INTERMEDIATEFILE=`realpath "output/vr/downscale/4k/intermediate/downscaled.mp4"`
				
				#nice "$FFMPEGPATHPREFIX"
				set -x
				ffmpeg -hide_banner -loglevel error -y -i "$newfn" -filter:v $TARGETSCALEOPT -c:a copy "$INTERMEDIATEFILE"
				set +x
				
				if [ -e $INTERMEDIATEFILE ]
				then
					[ -e "$EXIFTOOLBINARY" ] && "$EXIFTOOLBINARY" -all= -tagsfromfile "$newfn" -all:all -overwrite_original $INTERMEDIATEFILE && echo "tags copied."
					mv -f -- "$INTERMEDIATEFILE" "output/vr/downscale/$TARGETSIZE/$TARGETPREFIX""_$TARGETSIZE.mp4"
					mv -fv -- $newfn input/vr/downscale/$TARGETSIZE/done
				else
					echo -e $"\e[91mError:\e[0m creating loop failed. Missing file: output/vr/singleloop/intermediate/$TARGETPREFIX""_loop.mp4"
					mkdir -p input/vr/downscale/$TARGETSIZE/error
					mv -- $newfn input/vr/downscale/$TARGETSIZE/error
				fi
			else
				echo -e $"\e[91mError:\e[0m prompting failed. Missing file: $newfn"
			fi			
			
		done
	fi
	echo "Batch done.                             "
fi
