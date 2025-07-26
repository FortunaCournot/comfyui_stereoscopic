#!/bin/sh
# Executes the whole SBS workbench pipeline
# Copyright (c) 2025 Fortuna Cournot. MIT License.

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).
# Prerequisite: Placed sbs_api.py somewhere and configured path variables below.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable
COMFYUIPATH=.
# relative to COMFYUIPATH:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/i2i_upscale_downscale.sh 

cd $COMFYUIPATH

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

export CONFIGFILE
if [ -e $CONFIGFILE ] ; then
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
FPSRATE=2
# TRANSITION LENGTH (INTEGER). Minimum=0
TLENGTH=0

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
    echo "Error: ComfyUI not present. Ensure it is running on port 8188"
elif [[ $FREESPACE -lt $MINSPACE ]] ; then
	echo "Error: Less than $MINSPACE""G left on device: $FREESPACE""G"
else

	IMGFILES=`find input/vr/slides -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG'`
	COUNT=`find input/vr/slides -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
	INDEX=0
	INTERMEDIATEFOLDER=output/slides/intermediate
	TARGETFOLDER=output/slides
	mkdir -p "$INTERMEDIATEFOLDER"
	mkdir -p input/vr/slides/done
	rm -rf "$INTERMEDIATEFOLDER"/*  >/dev/null 2>&1
	
	if [[ $COUNT -gt 0 ]] ; then
	
		INPUTOPT=
		FILTEROPT=
		CURRENTOFFSET=0
		
		for nextinputfile in $IMGFILES ; do
			INDEX=$(( INDEX + 1 ))
			INDEXM1=$(( INDEX - 1 ))
			INDEXM2=$(( INDEX - 2 ))
			echo "$INDEX/$COUNT" >input/vr/scaling/BATCHPROGRESS.TXT
			
			newfn=${nextinputfile//[^[:alnum:.]]/}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			mv "$nextinputfile" $newfn 
			
			if [ -e "$newfn" ]; then
			
				/bin/bash $SCRIPTPATH "$newfn"
				
				TARGETPREFIX=${newfn##*/}
				if [ -e "output/vr/scaling/$TARGETPREFIX" ]; then
					SCRIPTRESULT=`ls output/vr/scaling/$TARGETPREFIX`
					TARGETPREFIX=${TARGETPREFIX%.*}
				else
					TARGETPREFIX=${TARGETPREFIX%.*}
					SCRIPTRESULT=`ls output/vr/scaling/$TARGETPREFIX*.png`
				fi
				
				if [ -e "$SCRIPTRESULT" ]; then 
				
					SCALINGINTERMEDIATE=
					RESULT=
					if test `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $newfn` -gt  `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $newfn`
					then
						echo "scaling against 4K-H"
						SCALINGINTERMEDIATE=tmpscalingH.png
						nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y  -i "$SCRIPTRESULT" -vf scale=3840:-1 "$SCALINGINTERMEDIATE"
						RESULT="$SCALINGINTERMEDIATE"
					else
						echo "scaling against 4K-V"
						SCALINGINTERMEDIATE=tmpscalingV.png
						nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y  -i "$SCRIPTRESULT" -vf scale=-1:3840 "$SCALINGINTERMEDIATE"
						RESULT="$SCALINGINTERMEDIATE"
					fi
					# ... this is possible in one step, but i am to lazy...
					if test `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $RESULT` -gt  2160
					then
						echo "scaling against 4K-D"
						SCALINGINTERMEDIATE=tmpscalingD.png
						nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y  -i "$RESULT" -vf scale=-1:2160 "$SCALINGINTERMEDIATE"
						RESULT="$SCALINGINTERMEDIATE"
					fi
					
					# Padding: ... this is maybe possible as well in one step, but i am to lazy...
					echo "padding..."
					SCALINGINTERMEDIATE=tmppadding.png
					nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i "$RESULT" -vf "scale=w=3840:h=2160:force_original_aspect_ratio=1,pad=3840:2160:(ow-iw)/2:(oh-ih)/2" "$SCALINGINTERMEDIATE"
					rm -f "$RESULT"
					RESULT="$SCALINGINTERMEDIATE"
					echo "padding done."
					
					if [ -e "$RESULT" ]; then
						mv $RESULT $TARGETFOLDER/$TARGETPREFIX".png"
						rm "$SCRIPTRESULT"
						mv -f "$newfn" input/vr/slides/done
						
					else
						echo "Error: Missing result: $RESULT"
						sleep 10
						exit
					fi
				else
					echo "Error: Missing script result: $SCRIPTRESULT. Please restart ComfyUI and try again."
					sleep 10
					exit
				fi
			fi			
		done
		echo "========== Images processed. Generating Slideshow ==========                         "
			
		
		rm input/vr/scaling/BATCHPROGRESS.TXT
		
	else
		# Not enought image files (png|jpg|jpeg) found in input/vr/slides. At least 2.
		echo "No images in input/vr/slides"
	fi	
	

fi

