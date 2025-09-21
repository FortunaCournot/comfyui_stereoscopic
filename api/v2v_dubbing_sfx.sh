#!/bin/sh
#
# v2v_dubbing.sh || exit 1
#
# dubbes a base video (input) by mmaudio and places result under ComfyUI/output/vr/dubbing/sfx folder.
#
# Copyright (c) 2025 Fortuna Cournot. MIT License. www.3d-gallery.org

# This ComfyUI API script needs addional custom node packages: 
#  MMAudio, Florence2

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).
# Prerequisite: Configured path variables below.
# Prerequisite: Git Bash installed. Call this script in Git Bash

# - It will split the input video into segements,
# - It queues dubbing workflows via api,
# - Creates a shell script for concating resulting audio segments and dubbes video
# - Waits until comfyui is done, then call created script.

# either start this script in ComfyUI folder or enter absolute path of ComfyUI folder in your ComfyUI_windows_portable here
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# API relative to COMFYUIPATH, or absolute path:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/python/v2v_dubbing.py
# Use Systempath for python by default, but set it explictly for comfyui portable.
PYTHON_BIN_PATH=
if [ -d "../python_embeded" ]; then
  PYTHON_BIN_PATH=../python_embeded/
fi

MAXAUDIOSEGMENTLENGTH=64	# hardcoded limit in py script
DUBSTRENGTH_ORIGINAL=1.75	# WEIGHT IF AUDIO IS ALREADY PRESENT
DUBSTRENGTH_AI=0.25			# WEIGHT IF AUDIO IS ALREADY PRESENT


if test $# -ne 1 
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 input"
    echo "E.g.: $0 SmallIconicTown.mp4"
	exit 1
elif [ ! -e "$COMFYUIPATH/models/mmaudio/apple_DFN5B-CLIP-ViT-H-14-384_fp16.safetensors" ]
then
	echo -e $"\e[91mError:\e[0m mmaudio models not yet installed. Follow guide at https://github.com/kijai/ComfyUI-MMAudio?tab=readme-ov-file#installation"
	exit 1
elif [ ! -e "$COMFYUIPATH/models/mmaudio/mmaudio_vae_44k_fp16.safetensors" ]
then
	echo -e $"\e[91mError:\e[0m mmaudio models not yet installed. Follow guide at https://github.com/kijai/ComfyUI-MMAudio?tab=readme-ov-file#installation"
	exit 1
elif [ ! -e "$COMFYUIPATH/models/mmaudio/mmaudio_large_44k_v2_fp16.safetensors" ]
then
	echo -e $"\e[91mError:\e[0m mmaudio models not yet installed. Follow guide at https://github.com/kijai/ComfyUI-MMAudio?tab=readme-ov-file#installation"
	exit 1
elif [ ! -e "$COMFYUIPATH/models/mmaudio/mmaudio_synchformer_fp16.safetensors" ]
then
	echo -e $"\e[91mError:\e[0m mmaudio models not yet installed. Follow guide at https://github.com/kijai/ComfyUI-MMAudio?tab=readme-ov-file#installation"
	exit 1
else
	
	cd $COMFYUIPATH

	CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

	NOLINE=-ne
	
	export CONFIGFILE
	if [ -e $CONFIGFILE ] ; then
		loglevel=$(awk -F "=" '/loglevel=/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
		[ $loglevel -ge 2 ] && set -x
		[ $loglevel -ge 2 ] && NOLINE="" ; echo $NOLINE
		config_version=$(awk -F "=" '/config_version=/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
		COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST=/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
		COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT=/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
		export COMFYUIHOST COMFYUIPORT
	else
		touch "$CONFIGFILE"
		echo "config_version=1">>"$CONFIGFILE"
	fi

	# set FFMPEGPATHPREFIX if ffmpeg binary is not in your enviroment path
	FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX=/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}

	EXIFTOOLBINARY=$(awk -F "=" '/EXIFTOOLBINARY=/ {print $2}' $CONFIGFILE) ; EXIFTOOLBINARY=${EXIFTOOLBINARY:-""}

	# fp16, sdpa. The model will automatic downloaded by Florence2 into ComfyUI/models/LLM.
	FLORENCE2MODEL=$(awk -F "=" '/FLORENCE2MODEL=/ {print $2}' $CONFIGFILE) ; FLORENCE2MODEL=${FLORENCE2MODEL:-"microsoft/Florence-2-base"}

	DUBBINGSEGMENTTING_THRESHOLD=$(awk -F "=" '/DUBBINGSEGMENTTING_THRESHOLD=/ {print $2}' $CONFIGFILE) ; DUBBINGSEGMENTTING_THRESHOLD=${DUBBINGSEGMENTTING_THRESHOLD:-"20"}
	DUBBINGSEGMENTTIME_DURATION=$(awk -F "=" '/DUBBINGSEGMENTTIME_DURATION=/ {print $2}' $CONFIGFILE) ; DUBBINGSEGMENTTIME_DURATION=${DUBBINGSEGMENTTIME_DURATION:-"5"}


	status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
	if [ "$status" = "closed" ]; then
		echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
		exit 1
	fi

	# Use Systempath for python by default, but set it explictly for comfyui portable.
	PYTHON_BIN_PATH=
	if [ -d "../python_embeded" ]; then
	  PYTHON_BIN_PATH=../python_embeded/
	fi

	INPUT="$1"

	if [ ! -e "$INPUT" ] ; then echo "input file removed: $INPUT"; exit 0; fi
	shift

	if [ ! -e "$INPUT" ] ; then
		echo -e $"\e[91mInternal Error:\e[0m Missing input $INPUT"
		exit 1
	fi
	
	mkdir -p output/vr/dubbing/sfx/intermediate
	
	`"$FFMPEGPATHPREFIX"ffprobe -hide_banner -v error -select_streams v:0 -show_entries stream=codec_type,codec_name,bit_rate,width,height,r_frame_rate,duration,nb_frames -of json -i "$INPUT" >output/vr/dubbing/sfx/intermediate/probe.txt`
	
	temp=`grep duration output/vr/dubbing/sfx/intermediate/probe.txt`
	temp=${temp#*:}
	temp="${temp%\"*}"
    temp="${temp#*\"}"
    temp="${temp%,*}"
    duration="${temp%.*}"
	duration=$(( duration ))
	if [ "$duration" -le "$DUBBINGSEGMENTTING_THRESHOLD" ]; then
		SEGMENTTIME=$(( $duration + 1 ))
		PARALLELITY=1
	else
		SEGMENTTIME=$DUBBINGSEGMENTTIME_DURATION
		PARALLELITY=1
	fi
	AUDIOSEGMENTLENGTH=$((SEGMENTTIME * PARALLELITY))

	if [ "$AUDIOSEGMENTLENGTH" -gt $MAXAUDIOSEGMENTLENGTH ]		# limitation to 8 maybe outdated now, but needs to be changed in python workflow as well (hardcoded).
	then
		echo -e $"\e[91mError:\e[0m Audio segmentlength may cause out of memory. AUDIOSEGMENTLENGTH="$AUDIOSEGMENTLENGTH" > 64. (SEGMENTTIME * PARALLELITY): $SEGMENTTIME * $PARALLELITY"
		exit 1
	fi

	PROGRESS=" "
	if [ -e input/vr/dubbing/sfx/BATCHPROGRESS.TXT ]
	then
		PROGRESS=`cat input/vr/dubbing/sfx/BATCHPROGRESS.TXT`" "
	fi
	regex="[^/]*$"
	echo "========== $PROGRESS""dubbing "`echo $INPUT | grep -oP "$regex"`" =========="
	
	TARGETPREFIX=${INPUT##*/}
	INPUT=`realpath "$INPUT"`
	TARGETPREFIX=output/vr/dubbing/sfx/intermediate/${TARGETPREFIX%.*}
	FINALTARGETFOLDER=`realpath "output/vr/dubbing/sfx"`
	
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
	POSITIVEPATH="$CONFIGPATH/dubbing_sfx_positive.txt"
	NEGATIVEPATH="$CONFIGPATH/dubbing_sfx_negative.txt"
	POSITIVEPATH=`realpath "$POSITIVEPATH"`
	NEGATIVEPATH=`realpath "$NEGATIVEPATH"`

	SPLITINPUT="$INPUT"
	height=`"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $SPLITINPUT`
	if [ $((height%2)) -ne 0 ];
	then
		nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i "$SPLITINPUT" -vcodec libx264 -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" -r 24 -an "$DUBBINGDIR/tmppadded.mp4"
		if [ ! -e "$DUBBINGDIR/tmppadded.mp4" ]
		then
			echo -e $"\e[91mError:\e[0m padding failed."
			exit 1
		fi
		echo "height odd - padded."
		SPLITINPUT="$DUBBINGDIR/tmppadded.mp4"
	fi

	DUBINPUT="$SPLITINPUT"
	if [[ "$DUBINPUT" == *"_SBS_LR"* ]] ; then
		nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i "$DUBINPUT" -vf "crop=iw/2:ih:0:0" "$DUBBINGDIR/tmpleft.mp4"
		echo "SBS LR detected"
		SPLITINPUT="$DUBBINGDIR/tmpleft.mp4"
	fi

	if [ -e "$DUBBINGDIR/concat.sh" ]
	then
		until [ "$queuecount" = "0" ]
		do
			sleep 1
			curl -silent "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json
			queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
			echo $NOLINE "Waiting for old queue to finish. queuecount: $queuecount         \r"
		done
		echo "recovering...                                                   "
		queuecount=
	fi
	
	AUDIOMAPOPT=
	if [ ! -e "$DUBBINGDIR/concat.sh" ]
	then
		echo $NOLINE "Splitting into segments..."
		set -x
		nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i "$SPLITINPUT" -c:v libx264 -vf "scale=w=800:h=800:force_original_aspect_ratio=decrease,pad=ceil(iw/2)*2:ceil(ih/2)*2" -crf 17 -map 0:v:0 $AUDIOMAPOPT -segment_time $SEGMENTTIME -g 9 -sc_threshold 0 -force_key_frames "expr:gte(t,n_forced*9)" -f segment -segment_start_number 1 -vcodec libx264 "$SEGDIR/segment%05d.mp4"
		set +x
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
		echo $NOLINE "Prompting $p/$PARALLELITY ...         \r"
		mkdir -p $DUBBINGDIR/$p

		SEGCOUNT=`find $SEGDIR -maxdepth 1 -type f -name 'segment*.mp4' | wc -l`

		declare -i i=0
		declare -i pindex=0
		declare -i dindex=1
		concatopt=""
		echo $NOLINE "Prompting $p/$PARALLELITY ($SEGCOUNT)...         \r"
		for f in "$SEGDIR"/segment*.mp4 ; do
			i=$((i+1))
			if [ $i -ge $p ]; then
				f2=${f%.mp4}
				f2=${f2#$SEGDIR/segment}

				if [ $pindex -eq 0 ]; then
					concatopt="concat:segment$f2.mp4"
				else
					concatopt="$concatopt|segment$f2.mp4"
				fi
				
				pindex=$((pindex+1))
				if [ $pindex -le $PARALLELITY ]; then

					TMPFILE=$DUBBINGDIR/currentvideosegment.mp4
					TMPFILE=`realpath "$TMPFILE"`
					cd "$SEGDIR"
					nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i "$concatopt" -c copy "$TMPFILE"
					cd "$COMFYUIPATH"
					
					echo $NOLINE "Prompting $p/$PARALLELITY: segment $dindex/$SEGCOUNT$itertimemsg           \r"
					
					echo -ne $"\e[91m" ; "$PYTHON_BIN_PATH"python.exe $SCRIPTPATH "$TMPFILE" "$DUBBINGDIR"/$p/dubsegment $AUDIOSEGMENTLENGTH "$POSITIVEPATH" "$NEGATIVEPATH" "$FLORENCE2MODEL" ; echo -ne $"\e[0m"
					
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
		runtime=$((end-startjob))
		echo "run $p/$PARALLELITY done. duration: $runtime""s.                              "

		cd "$DUBBINGDIR/$p"
		echo "" >list.txt
		COUNT=`find . -maxdepth 1 -type f -name '*.flac' | wc -l`
		if [[ $COUNT -eq 0 ]] ; then
			PARALLELITY=$p
			cd "$COMFYUIPATH"
			echo ""
			echo -e $"\e[91mError:\e[0m@$p/$PARALLELITY: No flac files!"
			#echo -e $"\e[93mWarning:\e[0m@$p/$PARALLELITY: No flac files. Skipped dubbing."
			#cp -fv $INPUT $FINALTARGETFOLDER
			#mkdir -p ./input/vr/dubbing/sfx/done
			#mv -fv $INPUT ./input/vr/dubbing/sfx/done
			exit 1
		else
			for f in *.flac; do
				"$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y  -i $f -af "afade=d=0.05,areverse,afade=d=0.05,areverse" "faded"$f
				echo "file 'faded$f'" >> list.txt
			done
			nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i list.txt -af anlmdn ../output$p.flac
			if [ ! -e "../output$p.flac" ]; then echo -e $"\e[93mWarning:\e[0mfailed to create output$p.flac" ; fi
			cd "$COMFYUIPATH"
			
			if [ $p -eq 1 ]; then
				if [ ! -e "$DUBBINGDIR/output1.flac" ]; then echo -e $"\e[91mError:\e[0m failed to create output$p.flac" && exit ; fi
				cp -v -- $DUBBINGDIR/output1.flac $DUBBINGDIR/merged.flac
			else
				# Combining two audio files and introducing an offset with FFMPEG
				# https://superuser.com/questions/1719361/combining-two-audio-files-and-introducing-an-offset-with-ffmpeg
				nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i $DUBBINGDIR/output$p.flac -i $DUBBINGDIR/merged.flac -filter_complex "aevalsrc=0:d=$(((p-1)*SEGMENTTIME))[s1];[s1][1:a]concat=n=2:v=0:a=1[ac2];[0:a]apad[ac1];[ac1][ac2]amerge=2[a]" -map "[a]" $DUBBINGDIR/merged-temp.flac
				if [ -e "$DUBBINGDIR/merged-temp.flac" ]; then
					mv -fv -- $DUBBINGDIR/merged-temp.flac $DUBBINGDIR/merged.flac
				else
					echo -e $"\e[93mWarning:\e[0m failed to create merged-temp.flac($p). This occurs for short video input (2 seconds)."
				fi
			fi
		fi
	done
	
	cd "$COMFYUIPATH"
	echo "Prompting done, dubbing...                               "
	
	if [ -e "$DUBBINGDIR/merged.flac" ]; then
		TESTAUDIO=`"$FFMPEGPATHPREFIX"ffprobe -i "$SPLITINPUT" -show_streams -select_streams a -loglevel error | head -n 1`
		AUDIOMAPOPT="-map 0:a:0"
		if [[ $TESTAUDIO =~ "[STREAM]" ]]; then
			nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i "$SPLITINPUT" -q:a 0 -map a $DUBBINGDIR/source.mp3
			if [ ! -e "$DUBBINGDIR/source.mp3" ]; then echo -e $"\e[91mError:\e[0m failed to create source.mp3" && exit ; fi
			#https://stackoverflow.com/questions/35509147/ffmpeg-amix-filter-volume-issue-with-inputs-of-different-duration
			nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i $DUBBINGDIR/source.mp3 -i "$DUBBINGDIR""/merged.flac" -filter_complex "[0]adelay=0|0,volume=$DUBSTRENGTH_ORIGINAL[a];[1]adelay=0|0,volume=$DUBSTRENGTH_AI[b];[a][b]amix=inputs=2:duration=longest:dropout_transition=0" $DUBBINGDIR/sourcemerge.flac
			if [ ! -e "$DUBBINGDIR/sourcemerge.flac" ]; then echo -e $"\e[91mError:\e[0m failed to create sourcemerge.flac" && exit ; fi
			nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -f lavfi -t 10 -i anullsrc=channel_layout=stereo:sample_rate=44100 -i $DUBBINGDIR/sourcemerge.flac -filter_complex "[1:a][0:a]concat=n=2:v=0:a=1" $DUBBINGDIR/padded.mp3
			if [ ! -e "$DUBBINGDIR/padded.mp3" ]; then echo -e $"\e[91mError:\e[0m failed to create padded.mp3" && exit ; fi
			# in 8.0 problems: -fflags +shortest
			nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i "$DUBINPUT" -i $DUBBINGDIR/padded.mp3 -map 0:v:0 -c:v libx264  -map 1:a:0 -c:a aac -shortest  $DUBBINGDIR/dubbed.mp4
			if [ ! -e "$DUBBINGDIR/dubbed.mp4" ]; then echo -e $"\e[91mError:\e[0m failed to create dubbed.mp4 (A)" && exit ; fi
		else
			nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -f lavfi -t 10 -i anullsrc=channel_layout=stereo:sample_rate=44100 -i "$DUBBINGDIR""/merged.flac" -filter_complex "[1:a][0:a]concat=n=2:v=0:a=1" $DUBBINGDIR/padded.mp3
			if [ ! -e "$DUBBINGDIR/padded.mp3" ]; then echo -e $"\e[91mError:\e[0m failed to create padded.mp3" && exit ; fi
			# in 8.0 problems: -fflags +shortest
			nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i "$DUBINPUT" -i $DUBBINGDIR/padded.mp3 -map 0:v:0 -c:v libx264  -map 1:a:0 -c:a aac -shortest  $DUBBINGDIR/dubbed.mp4
			if [ ! -e "$DUBBINGDIR/dubbed.mp4" ]; then echo -e $"\e[91mError:\e[0m failed to create dubbed.mp4 (NA)" && exit ; fi
		fi
		[ -e "$EXIFTOOLBINARY" ] && "$EXIFTOOLBINARY" -all= -tagsfromfile "$INPUT" -all:all -overwrite_original $DUBBINGDIR/dubbed.mp4 && echo "tags copied."
		TARGETFILEBASE=${TARGETPREFIX##*/}
		declare -i n=0    # Starting suffix number
		while [ -e output/vr/dubbing/sfx/"$TARGETFILEBASE""_dub"$(printf %03d "$((10#$n))" )".mp4" ]; do n=$((n+1)); done
		mv -f -- $DUBBINGDIR/dubbed.mp4 output/vr/dubbing/sfx/intermediate/"$TARGETFILEBASE""_dub"$(printf %03d "$((10#$n))" )".mp4"
		mv -vf -- output/vr/dubbing/sfx/intermediate/"$TARGETFILEBASE""_dub"$(printf %03d "$((10#$n))" )".mp4" "$FINALTARGETFOLDER"		
		rm -rf "$SEGDIR" "$DUBBINGDIR"
		mkdir -p ./input/vr/dubbing/sfx/done
		mv -fv $INPUT ./input/vr/dubbing/sfx/done
	else
		echo -e $"\e[91mError:\e[0m failed to create merged-temp.flac(final)."
		mkdir -p ./input/vr/dubbing/sfx/error
		mv -fv $INPUT ./input/vr/dubbing/sfx/error
		exit 0
	fi

	echo "Dubbing done."

fi
exit 0

