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
FPSRATE=2
# TRANSITION LENGTH (INTEGER). Minimum=0
TLENGTH=0

FREESPACE=$(df -khBG . | tail -n1 | awk '{print $4}')
FREESPACE=${FREESPACE%G}
MINSPACE=10
if test $# -ne 0
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 "
    echo "E.g.: $0 "
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

			echo -ne "Scaling $INDEX/$COUNT $INTERMEDPREFIX ...                              \r"
			
			
			newfn=${nextinputfile//[^[:alnum:.]]/}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			mv "$nextinputfile" $newfn 
			
			if [ -e "$newfn" ]; then
				SCALINGINTERMEDIATE=
				RESULT=
				if test `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $newfn` -gt  `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $newfn`
				then
					SCALINGINTERMEDIATE=tmpscalingH.png
					nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y  -i "$newfn" -vf scale=3840:-1 "$SCALINGINTERMEDIATE"
					RESULT="$SCALINGINTERMEDIATE"
				else
					SCALINGINTERMEDIATE=tmpscalingV.png
					nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y  -i "$newfn" -vf scale=-1:3840 "$SCALINGINTERMEDIATE"
					RESULT="$SCALINGINTERMEDIATE"
				fi
				if test `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $RESULT` -gt  2160
				then
					SCALINGINTERMEDIATE=tmpscalingD.png
					nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y  -i "$RESULT" -vf scale=-1:2160 "$SCALINGINTERMEDIATE"
					RESULT="$SCALINGINTERMEDIATE"
				fi
				mv -f "$newfn" input/slideshow_in/done
				if [ -e "$RESULT" ]; then
					mv $RESULT $INTERMEDIATEFOLDER/$INTERMEDPREFIX
					
					INPUTOPT="$INPUTOPT -loop 1 -t $DISPLAYLENGTH -i $INTERMEDIATEFOLDER/$INTERMEDPREFIX"
					TOFFSET=$(( DISPLAYLENGTH + TOFFSET - TLENGTH ))
					TRANSITION=`shuf -n1 -e fade hlslice hrslice vuslice vdslice`
					# Tested with ffmpeg git-2020-08-31-4a11a6f: hlslice hrslice vuslice vdslice
					# Tested: wipeleft wiperight wipeup wipedown slideleft slideright slideup slidedown
					# Untested: smoothleft smoothright smoothup smoothdown circlecrop rectcrop circleclose circleopen horzclose horzopen vertclose vertopen diagbl diagbr diagtl diagtr  dissolve pixelize radial hblur wipetl wipetr wipebl wipebr zoomin transition for xfade zoomin  coverleft coverright coverup coverdown revealleft revealright revealup revealdown
					# Problems: hlwind hrwind vuwind vdwind
					FILTER=xfade="transition=$TRANSITION:duration=$TLENGTH:offset=$TOFFSET"
					if [[ $TLENGTH -lt 1 ]] ; then
						TRANSITION="fade"
					fi
					if [[ $INDEX -gt 1 ]] ; then
						if [[ $INDEX -lt $COUNT ]] ; then
							FILTEROPT="$FILTEROPT"";[f"$INDEXM2"]["$INDEX"]FILTER[f"$INDEXM1"]"
						fi
					else
						FILTEROPT="[0][1]xfade=transition=$TRANSITION:duration=$TLENGTH:offset=$TOFFSET[f0]"
					fi
				else
					echo "\nError: Missing result: $RESULT"
					exit
				fi
			else
				echo "\nError: Missing input: $newfn"
				exit
			fi			
		done
		echo "Images processed.                                                  "
			
		NOW=$( date '+%F_%H%M' )	
		nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y $INPUTOPT -filter_complex $FILTEROPT -map "[f$INDEXM2]" -r $FPSRATE -pix_fmt yuv420p -vcodec libx264 $INTERMEDIATEFOLDER/output.mp4
		mv -f $INTERMEDIATEFOLDER/output.mp4 output/slideshow/slideshow-$NOW.mp4
		set +x
		
	else
		# Not enought image files (png|jpg|jpeg) found in input/slideshow_in. At least 2.
		echo "No images (2+) for slideshow in input/slideshow_in"
	fi	
	

fi

