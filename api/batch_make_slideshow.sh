#!/bin/sh
# Executes the whole SBS workbench pipeline
# Copyright (c) 2025 Fortuna Cournot. MIT License.

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).
# Prerequisite: Placed sbs_api.py somewhere and configured path variables below.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`


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

# Length of each Image to display in seconds (INTEGER)
DISPLAYLENGTH=6
# FPS Rate of the slideshow (INTEGER). Minimum=2
FPSRATE=25
# TRANSITION LENGTH (INTEGER). Minimum=0
TLENGTH=1

FREESPACE=$(df -khBG . | tail -n1 | awk '{print $4}')
FREESPACE=${FREESPACE%G}
MINSPACE=10
status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
if test $# -ne 0
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 "
    echo "E.g.: $0 "
elif [ "$status" = "closed" ]; then
    echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
elif [[ $FREESPACE -lt $MINSPACE ]] ; then
	echo -e $"\e[91mError:\e[0m Less than $MINSPACE""G left on device: $FREESPACE""G"
else

	IMGFILES=`find input/vr/slideshow -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG'`
	COUNT=`find input/vr/slideshow -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
	INDEX=0
	INTERMEDIATEFOLDER=output/vr/slideshow/intermediate
	mkdir -p "$INTERMEDIATEFOLDER"
	mkdir -p input/vr/slideshow/done
	rm -rf "$INTERMEDIATEFOLDER"/*  >/dev/null 2>&1
	
	if [[ $COUNT -gt 1 ]] ; then
	
		INPUTOPT=
		FILTEROPT=
		CURRENTOFFSET=0
		
		sleep 5 # extra time for transfer multiple files.
		
		for nextinputfile in $IMGFILES ; do
			INDEX=$(( INDEX + 1 ))
			INDEXM1=$(( INDEX - 1 ))
			INDEXM2=$(( INDEX - 2 ))
			INTERMEDPREFIX=${nextinputfile##*/}
			echo "$INDEX/$COUNT" >input/vr/slideshow/BATCHPROGRESS.TXT
			
			newfn=${nextinputfile##*/}
			newfn=input/vr/slideshow/${newfn//[^[:alnum:].]/_}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			mv "$nextinputfile" $newfn 
			
			if [ -e "$newfn" ]; then
			
				TARGETPREFIX=${newfn##*/}
				TARGETPREFIX=${TARGETPREFIX%.*}
				
				RESULT=$newfn
				
				if [ -e "$RESULT" ]; then
					INPUTOPT="$INPUTOPT -loop 1 -t $DISPLAYLENGTH -i $RESULT"
					TOFFSET=$(( DISPLAYLENGTH + TOFFSET - TLENGTH ))
					# 
					TRANSITION=`shuf -n1 -e fade vuslice vdslice smoothup smoothdown`
					# Tested with ffmpeg git-2020-08-31-4a11a6f: vuslice vdslice smoothup smoothdown dissolve.  
					# bad effect for VR: hlslice hrslice slideup slidedown slideleft slideright hblur pixelize radial dissolve
					# bad effect for VR: smoothleft smoothright   circlecrop rectcrop circleclose circleopen horzclose horzopen vertclose vertopen diagbl diagbr diagtl diagtr        coverleft coverright   
					# No support old version: hlwind hrwind vuwind vdwind zoomin wipeup wipedown revealleft revealright wipeleft wiperight  wipetl wipetr wipebl wipebr coverup coverdown
					FILTER=xfade="transition=$TRANSITION:duration=$TLENGTH:offset=$TOFFSET"
					if [[ $TLENGTH -lt 1 ]] ; then
						TRANSITION="fade"
					fi
					if [[ $INDEX -gt 1 ]] ; then
						if [[ $INDEX -lt $COUNT ]] ; then
							FILTEROPT="$FILTEROPT"";[f"$INDEXM2"]["$INDEX"]"$FILTER"[f"$INDEXM1"]"
						fi
					else
						FILTEROPT="[0][1]xfade=transition=$TRANSITION:duration=$TLENGTH:offset=$TOFFSET[f0]"
					fi
				else
					echo -e $"\e[91mError:\e[0m Missing result: $RESULT"
					sleep 10
					exit 1
				fi
			else
				echo -e $"\e[91mError:\e[0m Missing input: $newfn"
				sleep 10
				exit 1
			fi			
		done
		ESTIMATED_SLIDE_COUNT=$(( FPSRATE * INDEX * (DISPLAYLENGTH - 1) ))
		echo "Images processed. Generating Slideshow (~$ESTIMATED_SLIDE_COUNT frames) ...                         "
			
		NOW=$( date '+%F_%H%M' )	
		
		#set -x

		"$FFMPEGPATHPREFIX"ffmpeg -v error -hide_banner -stats -loglevel repeat+level+error -y $INPUTOPT -filter_complex $FILTEROPT -map "[f$INDEXM2]" -r $FPSRATE -pix_fmt yuv420p -vcodec libx264 $INTERMEDIATEFOLDER/output.mp4 

		echo -e $"\e[92mdone\e[0m                    "
		
		#set +x
		
		TARGET=output/vr/slideshow/"$TARGETPREFIX-slideshow-$NOW_SBS_LR.mp4"
		mv -f $INTERMEDIATEFOLDER/output.mp4 "$TARGET"
		rm input/vr/slideshow/BATCHPROGRESS.TXT
		mkdir -p input/vr/slideshow/done
		mv input/vr/slideshow/*.* input/vr/slideshow/done
		if [ ! -e "$TARGET" ]; then
			echo -e $"\e[91mError:\e[0m Failed to make slideshow"
			sleep 10
			exit 1
		fi
		
	else
		# Not enought image files (png|jpg|jpeg) found in input/vr/slideshow. At least 2.
		echo "Info: No images (2+) for slideshow in input/vr/slideshow"
	fi	
	

fi

