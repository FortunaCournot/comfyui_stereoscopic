#!/bin/sh
#
# v2v_dubbing.sh
#
# dubbes a base video (input) by mmaudio and places result under ComfyUI/output/dubbing folder.
#
# Copyright (c) 2025 FortunaCournot. MIT License.

# This ComfyUI API script needs addional custom node packages: 
#  MMAudio, Florence2

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).
# Prerequisite: Configured path variables below.
# Prerequisite: Git Bash installed. Call this script in Git Bash

# - It will split the input video into segements,
# - It queues dubbing workflows via api,
# - Creates a shell script for concating resulting audio segments and dubbes video
# - Waits until comfyui is done, then call created script.

# set FFMPEGPATH if ffmpeg binary is not in your enviroment path
FFMPEGPATH=
# either start this script in ComfyUI folder or enter absolute path of ComfyUI folder in your ComfyUI_windows_portable here
COMFYUIPATH=.
# API relative to COMFYUIPATH, or absolute path:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/v2v_dubbing.py
# Use Systempath for python by default, but set it explictly for comfyui portable.
PYTHON_BIN_PATH=
if [ -d "../python_embeded" ]; then
  PYTHON_BIN_PATH=../python_embeded/
fi

DUBSTRENGTH_ORIGINAL=1.75	# WEIGHT IF AUDIO IS ALREADY PRESENT
DUBSTRENGTH_AI=0.25			# WEIGHT IF AUDIO IS ALREADY PRESENT

SEGMENTTIME=2
PARALLELITY=2
AUDIOSEGMENTLENGTH=$((SEGMENTTIME * PARALLELITY))
if [ "$AUDIOSEGMENTLENGTH" -gt 8 ]
then
    echo "$0: Configuration error:  AUDIOSEGMENTLENGTH="$AUDIOSEGMENTLENGTH" > 8 "
	exit
fi

if test $# -ne 1 
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 input"
    echo "E.g.: $0 SmallIconicTown.mp4"
elif [ ! -d "$COMFYUIPATH/custom_nodes/ComfyUI-MMAudio" ]
then
		echo "Error: ComfyUI-MMAudio custom nodes not installed from https://github.com/kijai/ComfyUI-MMAudio. This needs manual setup, read the manual please. "
elif [ ! -e "$COMFYUIPATH/models/mmaudio/apple_DFN5B-CLIP-ViT-H-14-384_fp16.safetensors" ]
then
		echo "Error: mmaudio models not installed. This needs manual setup, read the manual on https://github.com/kijai/ComfyUI-MMAudio please."
elif [ ! -d "$COMFYUIPATH/custom_nodes/comfyui-florence2" ]
then
		echo "Error: comfyui-florence2 custom nodes not installed. Please install through ComfyUI Manager."
else
	cd $COMFYUIPATH

	COMFYUIPATH=`pwd`
	
	status=`true &>/dev/null </dev/tcp/127.0.0.1/8188 && echo open || echo closed`
	if [ "$status" = "closed" ]; then
		echo "Error: ComfyUI not present. Ensure it is running on port 8188"
		exit
	fi

	# Use Systempath for python by default, but set it explictly for comfyui portable.
	PYTHON_BIN_PATH=
	if [ -d "../python_embeded" ]; then
	  PYTHON_BIN_PATH=../python_embeded/
	fi

	INPUT="$1"
	shift

	PROGRESS=" "
	if [ -e input/dubbing_in/BATCHPROGRESS.TXT ]
	then
		PROGRESS=`cat input/dubbing_in/BATCHPROGRESS.TXT`" "
	fi
	regex="[^/]*$"
	echo "========== $PROGRESS""dubbing "`echo $INPUT | grep -oP "$regex"`" =========="
	
	TARGETPREFIX=${INPUT##*/}
	INPUT=`realpath "$INPUT"`
	TARGETPREFIX=output/dubbing/intermediate/${TARGETPREFIX%.mp4}
	FINALTARGETFOLDER=`realpath "output/dubbing"`
	
	FADEOUTSTART=$((SEGMENTTIME-1))
	
	mkdir -p "$TARGETPREFIX"".tmpseg"
	mkdir -p "$TARGETPREFIX"".tmpdubbing"
	SEGDIR=`realpath "$TARGETPREFIX"".tmpseg"`
	DUBBINGDIR=`realpath "$TARGETPREFIX"".tmpdubbing"`
	if [ ! -e "$DUBBINGDIR/concat.sh" ]
	then
		touch "$TARGETPREFIX"".tmpseg"/x
		touch "$TARGETPREFIX"".tmpdubbing"/x
		rm -rf "$TARGETPREFIX"".tmpseg"/* "$TARGETPREFIX"".tmpdubbing"/*
	fi
	touch $TARGETPREFIX
	TARGETPREFIX=`realpath "$TARGETPREFIX"`
	echo "prompting for $TARGETPREFIX"
	rm "$TARGETPREFIX"

	POSITIVEPATH="input/dubbing_in/positive.txt"
	NEGATIVEPATH="input/dubbing_in/negative.txt"
	if [ ! -e "$POSITIVEPATH" ]
	then
		echo "" >$POSITIVEPATH
	fi
	if [ ! -e "$NEGATIVEPATH" ]
	then
		echo "music, voice, crying." >$NEGATIVEPATH
	fi
	POSITIVEPATH=`realpath "$POSITIVEPATH"`
	NEGATIVEPATH=`realpath "$NEGATIVEPATH"`

	SPLITINPUT="$INPUT"
	if [ -e "$DUBBINGDIR/concat.sh" ]
	then
		until [ "$queuecount" = "0" ]
		do
			sleep 1
			curl -silent "http://127.0.0.1:8188/prompt" >queuecheck.json
			queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
			echo -ne "Waiting for old queue to finish. queuecount: $queuecount         \r"
		done
		echo "recovering...                                                   "
		queuecount=
	fi
	
	AUDIOMAPOPT=
	if [ ! -e "$DUBBINGDIR/concat.sh" ]
	then
		echo -ne "Splitting into segments..."
		nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i "$SPLITINPUT" -c:v libx264 -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" -crf 22 -map 0:v:0 $AUDIOMAPOPT -segment_time $SEGMENTTIME -g 9 -sc_threshold 0 -force_key_frames "expr:gte(t,n_forced*9)" -f segment -segment_start_number 1 -vcodec libx264 "$SEGDIR/segment%05d.ts"
		echo "done.                                               "
	fi
	 
	#PINPUTOPT=
	for ((p=1; p<=$PARALLELITY; p++))
	do
		echo -ne "Prompting $p/$PARALLELITY ...         \r"
		mkdir -p $DUBBINGDIR/$p

		i=0
		pindex=0
		dindex=1
		concatopt=""
		for f in "$SEGDIR"/segment*.ts ; do
			i=$((i+1))
			if [ $i -ge $p ]; then
				f2=${f%.ts}
				f2=${f2#$SEGDIR/segment}

				if [ $pindex -eq 0 ]; then
					concatopt="concat:segment$f2.ts"
				else
					concatopt="$concatopt|segment$f2.ts"
				fi
				
				pindex=$((pindex+1))
				if [ $pindex -ge $PARALLELITY ]; then

					TMPFILE=$DUBBINGDIR/currentvideosegment.ts
					TMPFILE=`realpath "$TMPFILE"`
					cd "$SEGDIR"
					nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i "$concatopt" -c copy "$TMPFILE"
					cd "$COMFYUIPATH"
					
					echo -ne "Prompting $p/$PARALLELITY: segment #$dindex ...                                 \r"
					
					"$PYTHON_BIN_PATH"python.exe $SCRIPTPATH "$TMPFILE" "$DUBBINGDIR"/$p/dubsegment $AUDIOSEGMENTLENGTH $POSITIVEPATH $NEGATIVEPATH
					
					queuecount=
					until [ "$queuecount" = "0" ]
					do
						sleep 1
						curl -silent "http://127.0.0.1:8188/prompt" >queuecheck.json
						queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
					done
					
					rm $TMPFILE
					
					dindex=$((dindex+1))
					pindex=0					
				fi

			fi
		done

		cd "$DUBBINGDIR/$p"
		echo "" >list.txt
		for f in *.flac; do echo "file '$f'" >> list.txt; done
		nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i list.txt -af anlmdn ../output$p.flac
		if [ ! -e "../output$p.flac" ]; then echo "Warning: failed to create output$p.flac" ; fi
		cd "$COMFYUIPATH"
		
		if [ $p -eq 1 ]; then
			if [ ! -e "$DUBBINGDIR/output1.flac" ]; then echo "Error: failed to create output$p.flac" && exit ; fi
			cp $DUBBINGDIR/output1.flac $DUBBINGDIR/merged.flac
		else
			# Combining two audio files and introducing an offset with FFMPEG
			# https://superuser.com/questions/1719361/combining-two-audio-files-and-introducing-an-offset-with-ffmpeg
			nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i $DUBBINGDIR/output$p.flac -i $DUBBINGDIR/merged.flac -filter_complex "aevalsrc=0:d=$(((p-1)*SEGMENTTIME))[s1];[s1][1:a]concat=n=2:v=0:a=1[ac2];[0:a]apad[ac1];[ac1][ac2]amerge=2[a]" -map "[a]" $DUBBINGDIR/merged-temp.flac
			if [ -e "$DUBBINGDIR/merged-temp.flac" ]; then
				mv -f $DUBBINGDIR/merged-temp.flac $DUBBINGDIR/merged.flac
			else
				echo "Warning: failed to create merged-temp.flac($p)"
			fi
		fi

	done
	echo "Prompting done, dubbing...                               "
	
	if [ -e "$DUBBINGDIR/merged.flac" ]; then
		mv $DUBBINGDIR/merged.flac "$TARGETPREFIX"".flac"
		
		TESTAUDIO=`"$FFMPEGPATH"ffprobe -i "$SPLITINPUT" -show_streams -select_streams a -loglevel error`
		AUDIOMAPOPT="-map 0:a:0"
		if [[ $TESTAUDIO =~ "[STREAM]" ]]; then
			nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i "$SPLITINPUT" -q:a 0 -map a $DUBBINGDIR/source.mp3
			if [ ! -e "$DUBBINGDIR/source.mp3" ]; then echo "Error: failed to create source.mp3" && exit ; fi
			#https://stackoverflow.com/questions/35509147/ffmpeg-amix-filter-volume-issue-with-inputs-of-different-duration
			nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i $DUBBINGDIR/source.mp3 -i "$TARGETPREFIX"".flac" -filter_complex "[0]adelay=0|0,volume=$DUBSTRENGTH_ORIGINAL[a];[1]adelay=0|0,volume=$DUBSTRENGTH_AI[b];[a][b]amix=inputs=2:duration=longest:dropout_transition=0" $DUBBINGDIR/sourcemerge.flac
			if [ ! -e "$DUBBINGDIR/sourcemerge.flac" ]; then echo "Error: failed to create sourcemerge.flac" && exit ; fi
			nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i "$SPLITINPUT" -i $DUBBINGDIR/sourcemerge.flac -c:v copy -map 0:v:0 -map 1:a:0 $DUBBINGDIR/dubbed.mp4
			if [ ! -e "$DUBBINGDIR/dubbed.mp4" ]; then echo "Error: failed to create dubbed.mp4 (A)" && exit ; fi
		else
			nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i "$SPLITINPUT" -i "$TARGETPREFIX"".flac" -c:v copy -map 0:v:0 -map 1:a:0 $DUBBINGDIR/dubbed.mp4
			if [ ! -e "$DUBBINGDIR/dubbed.mp4" ]; then echo "Error: failed to create dubbed.mp4 (NA)" && exit ; fi
		fi
		mv -f $DUBBINGDIR/dubbed.mp4 "$TARGETPREFIX""_dub.mp4"
		mv -vf "$TARGETPREFIX""_dub.mp4" "$FINALTARGETFOLDER"
		
		rm -rf "$TARGETPREFIX"".tmpseg" "$TARGETPREFIX"".tmpdubbing"
		mkdir -p ./input/dubbing_in/done
		mv -fv $INPUT ./input/dubbing_in/done
	fi

	echo "Dubbing done."

fi

