#!/bin/sh
# Executes the whole SBS workbench pipeline
# Copyright (c) 2025 Fortuna Cournot. MIT License.

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).
# Prerequisite: Placed sbs_api.py somewhere and configured path variables below.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable
COMFYUIPATH=.


cd $COMFYUIPATH

# Length of each Image to display in seconds (INTEGER)
DISPLAYLENGTH=6
# FPS Rate of the slideshow (INTEGER). Minimum=2
FPSRATE=25
# TRANSITION LENGTH (INTEGER). Minimum=0
TLENGTH=1

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

	IMGFILES=`find input/slideshow_in -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG'`
	COUNT=`find input/slideshow_in -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
	INDEX=0
	INTERMEDIATEFOLDER=output/slideshow/intermediate
	mkdir -p "$INTERMEDIATEFOLDER"
	mkdir -p input/slideshow_in/done
	rm -rf "$INTERMEDIATEFOLDER"/*  >/dev/null 2>&1
	
	if [[ $COUNT -gt 1 ]] ; then
	
		INPUTOPT=
		FILTEROPT=
		CURRENTOFFSET=0
		
		for nextinputfile in $IMGFILES ; do
			INDEX=$(( INDEX + 1 ))
			INDEXM1=$(( INDEX - 1 ))
			INDEXM2=$(( INDEX - 2 ))
			INTERMEDPREFIX=${nextinputfile##*/}
			echo "$INDEX/$COUNT" >input/slideshow_in/BATCHPROGRESS.TXT
			
			
			
			newfn=${nextinputfile//[^[:alnum:.]]/}
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
					echo "Error: Missing result: $RESULT"
					sleep 10
					exit
				fi
			else
				echo "Error: Missing input: $newfn"
				sleep 10
				exit
			fi			
		done
		echo "Images processed. Generating Slideshow ...                         "
			
		NOW=$( date '+%F_%H%M' )	
		set -x
		nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y $INPUTOPT -filter_complex $FILTEROPT -map "[f$INDEXM2]" -r $FPSRATE -pix_fmt yuv420p -vcodec libx264 $INTERMEDIATEFOLDER/output.mp4
		set +x
		mv -f $INTERMEDIATEFOLDER/output.mp4 output/slideshow/slideshow-$NOW.mp4
		rm input/slideshow_in/BATCHPROGRESS.TXT
		if [ -e "output/slideshow/slideshow-$NOW.mp4" ]; then
			mv input/slideshow_in/*.* input/slideshow_in/done
		fi
		
	else
		# Not enought image files (png|jpg|jpeg) found in input/slideshow_in. At least 2.
		echo "No images (2+) for slideshow in input/slideshow_in"
	fi	
	

fi

