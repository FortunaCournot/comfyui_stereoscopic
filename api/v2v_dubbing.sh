#!/bin/sh
#
# v2v_dubbing.sh
#
# dubbes a base video (input) by mmaudio and places result under ComfyUI/output/vr/dubbing folder.
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
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/python/v2v_dubbing.py
# Use Systempath for python by default, but set it explictly for comfyui portable.
PYTHON_BIN_PATH=
if [ -d "../python_embeded" ]; then
  PYTHON_BIN_PATH=../python_embeded/
fi

# fp16, sdpa. The model will automatic downloaded by Florence2 into ComfyUI/models/LLM.
FLORENCE2MODEL="microsoft/Florence-2-base"

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
		echo -e $"\e[91mError:\e[0m ComfyUI-MMAudio custom nodes not installed from https://github.com/kijai/ComfyUI-MMAudio. This needs manual setup, read the manual please. "
elif [ ! -e "$COMFYUIPATH/models/mmaudio/apple_DFN5B-CLIP-ViT-H-14-384_fp16.safetensors" ]
then
		echo -e $"\e[91mError:\e[0m mmaudio models not installed. This needs manual setup, read the manual on https://github.com/kijai/ComfyUI-MMAudio please."
elif [ ! -d "$COMFYUIPATH/custom_nodes/comfyui-florence2" ]
then
		echo -e $"\e[91mError:\e[0m comfyui-florence2 custom nodes not installed. Please install through ComfyUI Manager."
else
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

	COMFYUIPATH=`pwd`
	
	status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
	if [ "$status" = "closed" ]; then
		echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
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
	if [ -e input/vr/dubbing/BATCHPROGRESS.TXT ]
	then
		PROGRESS=`cat input/vr/dubbing/BATCHPROGRESS.TXT`" "
	fi
	regex="[^/]*$"
	echo "========== $PROGRESS""dubbing "`echo $INPUT | grep -oP "$regex"`" =========="
	
	TARGETPREFIX=${INPUT##*/}
	INPUT=`realpath "$INPUT"`
	TARGETPREFIX=output/vr/dubbing/intermediate/${TARGETPREFIX%.mp4}
	FINALTARGETFOLDER=`realpath "output/vr/dubbing"`
	
	FADEOUTSTART=$((SEGMENTTIME-1))
	
	uuid=$(openssl rand -hex 16)
	mkdir -p "$TARGETPREFIX""-$uuid"".tmpseg"
	mkdir -p "$TARGETPREFIX"".tmpdubbing"
	SEGDIR=`realpath "$TARGETPREFIX""-$uuid"".tmpseg"`
	DUBBINGDIR=`realpath "$TARGETPREFIX"".tmpdubbing"`
	if [ ! -e "$DUBBINGDIR/concat.sh" ]
	then
		touch "$TARGETPREFIX""-$uuid"".tmpseg"/x
		touch "$TARGETPREFIX"".tmpdubbing"/x
		rm -rf "$TARGETPREFIX""-$uuid"".tmpseg"/* "$TARGETPREFIX"".tmpdubbing"/*
	fi
	touch $TARGETPREFIX
	TARGETPREFIX=`realpath "$TARGETPREFIX"`
	echo "prompting for $TARGETPREFIX"
	rm "$TARGETPREFIX"

	CONFIGPATH=user/default/comfyui_stereoscopic
	POSITIVEPATH="$CONFIGPATH/dubbing_positive.txt"
	NEGATIVEPATH="$CONFIGPATH/dubbing_negative.txt"
	if [ ! -e "$POSITIVEPATH" ]
	then
		mkdir -p $CONFIGPATH
		echo "" >$POSITIVEPATH
	fi
	if [ ! -e "$NEGATIVEPATH" ]
	then
		mkdir -p $CONFIGPATH
		echo "music, voice, crying." >$NEGATIVEPATH
	fi
	POSITIVEPATH=`realpath "$POSITIVEPATH"`
	NEGATIVEPATH=`realpath "$NEGATIVEPATH"`

	SPLITINPUT="$INPUT"
	height=`"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $SPLITINPUT`
	if [ $((height%2)) -ne 0 ];
	then
		nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i "$SPLITINPUT" -vcodec libx264 -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" -r 24 -an "$DUBBINGDIR/tmppadded.mp4"
		if [ ! -e "$DUBBINGDIR/tmppadded.mp4" ]
		then
			echo -e $"\e[91mError:\e[0m padding failed."
			exit
		fi
		echo "height odd - padded."
		SPLITINPUT="$DUBBINGDIR/tmppadded.mp4"
	fi
	
	if [ -e "$DUBBINGDIR/concat.sh" ]
	then
		until [ "$queuecount" = "0" ]
		do
			sleep 1
			curl -silent "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json
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
	lastcount=""
	start=`date +%s`
	end=`date +%s`
	startjob=$start
	itertimemsg=""
	for ((p=1; p<=$PARALLELITY; p++))
	do
		echo -ne "Prompting $p/$PARALLELITY ...         \r"
		mkdir -p $DUBBINGDIR/$p

		SEGCOUNT=`find $SEGDIR -maxdepth 1 -type f -name 'segment*.ts' | wc -l`

		i=0
		pindex=0
		dindex=1
		concatopt=""
		echo -ne "Prompting $p/$PARALLELITY ($SEGCOUNT)...         \r"
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
					
					echo -ne "Prompting $p/$PARALLELITY: segment $dindex/$SEGCOUNT$itertimemsg           \r"
					
					"$PYTHON_BIN_PATH"python.exe $SCRIPTPATH "$TMPFILE" "$DUBBINGDIR"/$p/dubsegment $AUDIOSEGMENTLENGTH "$POSITIVEPATH" "$NEGATIVEPATH" "$FLORENCE2MODEL"
					
					queuecount=
					until [ "$queuecount" = "0" ]
					do
						sleep 1
						curl -silent "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json
						queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
					done

					end=`date +%s`
					runtime=$((end-start))
					start=`date +%s`
					secs=$(( $SEGCOUNT * $PARALLELITY * $runtime ))
					eta=`printf '%02d:%02d:%02s\n' $((secs/3600)) $((secs%3600/60)) $((secs%60))`
					itertimemsg=", $runtime""s/prompt, ETA in $eta"

					rm $TMPFILE
					
					dindex=$((dindex+1))
					pindex=0					
				fi

			fi
		done
		echo "done. duration: $runtime""s.                                       "

		cd "$DUBBINGDIR/$p"
		echo "" >list.txt
		COUNT=`find . -maxdepth 1 -type f -name '*.flac' | wc -l`
		if [[ $COUNT -eq 0 ]] ; then
			echo ""
			echo -e $"\e[93mWarning:\e[0mno flac files. Just copying source..."
			cp -fv $INPUT $FINALTARGETFOLDER
			mkdir -p ./input/vr/dubbing/done
			mv -fv $INPUT ./input/vr/dubbing/done
			rm -rf "$TARGETPREFIX"".tmpseg" "$TARGETPREFIX"".tmpdubbing"
			exit
		fi
		
		for f in *.flac; do echo "file '$f'" >> list.txt; done
		nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i list.txt -af anlmdn ../output$p.flac
		if [ ! -e "../output$p.flac" ]; then echo -e $"\e[93mWarning:\e[0mfailed to create output$p.flac" ; fi
		cd "$COMFYUIPATH"
		
		if [ $p -eq 1 ]; then
			if [ ! -e "$DUBBINGDIR/output1.flac" ]; then echo -e $"\e[91mError:\e[0m failed to create output$p.flac" && exit ; fi
			cp $DUBBINGDIR/output1.flac $DUBBINGDIR/merged.flac
		else
			# Combining two audio files and introducing an offset with FFMPEG
			# https://superuser.com/questions/1719361/combining-two-audio-files-and-introducing-an-offset-with-ffmpeg
			nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i $DUBBINGDIR/output$p.flac -i $DUBBINGDIR/merged.flac -filter_complex "aevalsrc=0:d=$(((p-1)*SEGMENTTIME))[s1];[s1][1:a]concat=n=2:v=0:a=1[ac2];[0:a]apad[ac1];[ac1][ac2]amerge=2[a]" -map "[a]" $DUBBINGDIR/merged-temp.flac
			if [ -e "$DUBBINGDIR/merged-temp.flac" ]; then
				mv -f $DUBBINGDIR/merged-temp.flac $DUBBINGDIR/merged.flac
			else
				echo -e $"\e[93mWarning:\e[0mfailed to create merged-temp.flac($p). This occurs for short video input (2 seconds)."
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
			if [ ! -e "$DUBBINGDIR/source.mp3" ]; then echo -e $"\e[91mError:\e[0m failed to create source.mp3" && exit ; fi
			#https://stackoverflow.com/questions/35509147/ffmpeg-amix-filter-volume-issue-with-inputs-of-different-duration
			nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i $DUBBINGDIR/source.mp3 -i "$TARGETPREFIX"".flac" -filter_complex "[0]adelay=0|0,volume=$DUBSTRENGTH_ORIGINAL[a];[1]adelay=0|0,volume=$DUBSTRENGTH_AI[b];[a][b]amix=inputs=2:duration=longest:dropout_transition=0" $DUBBINGDIR/sourcemerge.flac
			if [ ! -e "$DUBBINGDIR/sourcemerge.flac" ]; then echo -e $"\e[91mError:\e[0m failed to create sourcemerge.flac" && exit ; fi
			nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -f lavfi -t 10 -i anullsrc=channel_layout=stereo:sample_rate=44100 -i $DUBBINGDIR/sourcemerge.flac -filter_complex "[1:a][0:a]concat=n=2:v=0:a=1" $DUBBINGDIR/padded.flac
			if [ ! -e "$DUBBINGDIR/padded.flac" ]; then echo -e $"\e[91mError:\e[0m failed to create padded.flac" && exit ; fi
			nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i "$SPLITINPUT" -i $DUBBINGDIR/padded.flac -shortest -map 0:v:0 -map 1:a:0 $DUBBINGDIR/dubbed.mp4
			if [ ! -e "$DUBBINGDIR/dubbed.mp4" ]; then echo -e $"\e[91mError:\e[0m failed to create dubbed.mp4 (A)" && exit ; fi
		else
			nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -f lavfi -t 10 -i anullsrc=channel_layout=stereo:sample_rate=44100 -i "$TARGETPREFIX"".flac" -filter_complex "[1:a][0:a]concat=n=2:v=0:a=1" $DUBBINGDIR/padded.flac
			if [ ! -e "$DUBBINGDIR/padded.flac" ]; then echo -e $"\e[91mError:\e[0m failed to create padded.flac" && exit ; fi
			nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i "$SPLITINPUT" -i $DUBBINGDIR/padded.flac -shortest -map 0:v:0 -map 1:a:0 $DUBBINGDIR/dubbed.mp4
			if [ ! -e "$DUBBINGDIR/dubbed.mp4" ]; then echo -e $"\e[91mError:\e[0m failed to create dubbed.mp4 (NA)" && exit ; fi
		fi
		mv -f $DUBBINGDIR/dubbed.mp4 "$TARGETPREFIX""_dub.mp4"
		mv -vf "$TARGETPREFIX""_dub.mp4" "$FINALTARGETFOLDER"
		
		rm -rf "$TARGETPREFIX"".tmpseg" "$TARGETPREFIX"".tmpdubbing"
		mkdir -p ./input/vr/dubbing/done
		mv -fv $INPUT ./input/vr/dubbing/done
	fi

	echo "Dubbing done."

fi

