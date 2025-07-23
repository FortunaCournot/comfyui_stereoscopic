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

# Length of each Image to display in seconds (INTEGER)
DISPLAYLENGTH=6
# FPS Rate of the slideshow (INTEGER). Minimum=2
FPSRATE=2
# TRANSITION LENGTH (INTEGER). Minimum=0
TLENGTH=0

FREESPACE=$(df -khBG . | tail -n1 | awk '{print $4}')
FREESPACE=${FREESPACE%G}
MINSPACE=10
status=`true &>/dev/null </dev/tcp/127.0.0.1/8188 && echo open || echo closed`
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

	IMGFILES=`find input/slides_in -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG'`
	COUNT=`find input/slides_in -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
	INDEX=0
	INTERMEDIATEFOLDER=output/slides/intermediate
	TARGETFOLDER=output/slides
	mkdir -p "$INTERMEDIATEFOLDER"
	mkdir -p input/slides_in/done
	rm -rf "$INTERMEDIATEFOLDER"/*  >/dev/null 2>&1
	
	if [[ $COUNT -gt 0 ]] ; then
	
		INPUTOPT=
		FILTEROPT=
		CURRENTOFFSET=0
		
		for nextinputfile in $IMGFILES ; do
			INDEX=$(( INDEX + 1 ))
			INDEXM1=$(( INDEX - 1 ))
			INDEXM2=$(( INDEX - 2 ))
			echo "$INDEX/$COUNT" >input/upscale_in/BATCHPROGRESS.TXT
			
			newfn=${nextinputfile//[^[:alnum:.]]/}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			mv "$nextinputfile" $newfn 
			
			if [ -e "$newfn" ]; then
			
				/bin/bash $SCRIPTPATH "$newfn"
				
				TARGETPREFIX=${newfn##*/}
				TARGETPREFIX=${TARGETPREFIX%.*}
				SCRIPTRESULT=`ls output/upscale/$TARGETPREFIX*.png`
				if [ -e "$SCRIPTRESULT" ]; then
				
					SCALINGINTERMEDIATE=
					RESULT=
					if test `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $newfn` -gt  `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $newfn`
					then
						SCALINGINTERMEDIATE=tmpscalingH.png
						nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y  -i "$SCRIPTRESULT" -vf scale=3840:-1 "$SCALINGINTERMEDIATE"
						RESULT="$SCALINGINTERMEDIATE"
					else
						SCALINGINTERMEDIATE=tmpscalingV.png
						nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y  -i "$SCRIPTRESULT" -vf scale=-1:3840 "$SCALINGINTERMEDIATE"
						RESULT="$SCALINGINTERMEDIATE"
					fi
					# ... this is possible in one step, but i am to lazy...
					if test `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $RESULT` -gt  2160
					then
						SCALINGINTERMEDIATE=tmpscalingD.png
						nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y  -i "$RESULT" -vf scale=-1:2160 "$SCALINGINTERMEDIATE"
						RESULT="$SCALINGINTERMEDIATE"
					fi
					
					# Padding: ... this is maybe possible as well in one step, but i am to lazy...
					SCALINGINTERMEDIATE=tmppadding.png
					nice "$FFMPEGPATH"ffmpeg -i "$RESULT" -vf "scale=w=3840:h=2160:force_original_aspect_ratio=1,pad=3840:2160:(ow-iw)/2:(oh-ih)/2" "$SCALINGINTERMEDIATE"
					rm -f "$RESULT"
					RESULT="$SCALINGINTERMEDIATE"
					
					if [ -e "$RESULT" ]; then
						mv $RESULT $TARGETFOLDER/$TARGETPREFIX".png"
						rm "$SCRIPTRESULT"
						mv -f "$newfn" input/slides_in/done
						
					else
						echo "Error: Missing result: $RESULT"
						sleep 10
						exit
					fi
				else
					echo "Error: Missing script result: $SCRIPTRESULT"
					sleep 10
					exit
				fi
			else
				echo "Error: Missing input: $newfn"
				sleep 10
				exit
			fi			
		done
		echo "========== Images processed. Generating Slideshow ==========                         "
			
		
		rm input/upscale_in/BATCHPROGRESS.TXT
		
	else
		# Not enought image files (png|jpg|jpeg) found in input/slides_in. At least 2.
		echo "No images in input/slides_in"
	fi	
	

fi

