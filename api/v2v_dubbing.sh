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
	TARGETPREFIX=output/dubbing/${TARGETPREFIX%.mp4}
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
		echo "recovering...                                                             "
		queuecount=
	fi
	
	AUDIOMAPOPT=
	if [ ! -e "$DUBBINGDIR/concat.sh" ]
	then
		echo -ne "Splitting into segments..."
		nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i "$SPLITINPUT" -c:v libx264 -crf 22 -map 0:v:0 $AUDIOMAPOPT -segment_time $SEGMENTTIME -g 9 -sc_threshold 0 -force_key_frames "expr:gte(t,n_forced*9)" -f segment -segment_start_number 1 -vcodec libx264 "$SEGDIR/segment%05d.ts"
		echo "done.                                                          "
	fi
	 
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
					"$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i "$concatopt" -c copy "$TMPFILE"
					cd "$COMFYUIPATH"
					
					echo -ne "$p/$PARALLELITY: Prompting $dindex ...                                 \r"
					
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


	done
	echo "Prompting done.                                                          "
	set +x
	
	echo "Jobs running...                                                          "
echo "exit"
exit


for i in *.flac; do
	FADEOUTSTART=$((SEGMENTTIME-1))
	nice ffmpeg -hide_banner -loglevel error -y -ss 0 -i $i -af "afade=type=in:start_time=0:duration=1,afade=type=out:start_time=$FADEOUTSTART:duration=1" -c:a libmp3lame faded.flac
	mv faded.flac $i
	echo "file $i">>list.txt
done

	
	echo "#!/bin/sh" >"$DUBBINGDIR/concat.sh"
	echo "cd \"\$(dirname \"\$0\")\"" >>"$DUBBINGDIR/concat.sh"
	echo "rm -rf \"$TARGETPREFIX\"\".tmpseg\"" >>"$DUBBINGDIR/concat.sh"
	echo "if [ -e ./sbssegment_00001-audio.mp4 ]" >>"$DUBBINGDIR/concat.sh"
	echo "then" >>"$DUBBINGDIR/concat.sh"
	echo "    list=\`find . -type f -print | grep mp4 | grep -v audio\`" >>"$DUBBINGDIR/concat.sh"
	echo "    rm \$list" >>"$DUBBINGDIR/concat.sh"
	echo "fi" >>"$DUBBINGDIR/concat.sh"
	echo "for f in ./*.mp4 ; do" >>"$DUBBINGDIR/concat.sh"
	echo "	echo \"file \$f\" >> "$DUBBINGDIR"/list.txt" >>"$DUBBINGDIR/concat.sh"
	echo "done" >>"$DUBBINGDIR/concat.sh"
	echo "$FFMPEGPATH""ffprobe -i $INPUT -show_streams -select_streams a -loglevel error >TESTAUDIO.txt 2>&1"  >>"$DUBBINGDIR/concat.sh"
	echo "TESTAUDIO=\`cat TESTAUDIO.txt\`"  >>"$DUBBINGDIR/concat.sh"
	echo "files=(*.mp4)"  >>"$DUBBINGDIR/concat.sh"
	echo "nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i \${files[0]} -vf \"thumbnail\" -frames:v 1 thumbnail.png" >>"$DUBBINGDIR/concat.sh"
	echo "if [[ \"\$TESTAUDIO\" =~ \"[STREAM]\" ]]; then" >>"$DUBBINGDIR/concat.sh"
	echo "    nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i list.txt -c copy output.mp4" >>"$DUBBINGDIR/concat.sh"
	echo "    nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i output.mp4 -i $INPUT -c copy -map 0:v:0 -map 1:a:0 output2.mp4" >>"$DUBBINGDIR/concat.sh"
	echo "    nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i output2.mp4 -i thumbnail.png -map 1 -map 0 -c copy -disposition:0 attached_pic $TARGETPREFIX"".mp4" >>"$DUBBINGDIR/concat.sh"
	echo "else" >>"$DUBBINGDIR/concat.sh"
	echo "    nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i list.txt -c copy output2.mp4" >>"$DUBBINGDIR/concat.sh"
	echo "    nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i output2.mp4 -i thumbnail.png -map 1 -map 0 -c copy -disposition:0 attached_pic $TARGETPREFIX"".mp4" >>"$DUBBINGDIR/concat.sh"
	echo "fi" >>"$DUBBINGDIR/concat.sh"
	echo "mkdir -p $FINALTARGETFOLDER" >>"$DUBBINGDIR/concat.sh"
	echo "mv $TARGETPREFIX"".mp4"" $FINALTARGETFOLDER" >>"$DUBBINGDIR/concat.sh"
	echo "cd .." >>"$DUBBINGDIR/concat.sh"
	echo "rm -rf \"$TARGETPREFIX\"\".tmpdubbing\"" >>"$DUBBINGDIR/concat.sh"
	echo "echo done." >>"$DUBBINGDIR/concat.sh"
	
	echo "Waiting for queue to finish..."
	sleep 4  # Give some extra time to start...
	lastcount=""
	start=`date +%s`
	startjob=$start
	itertimemsg=""
	until [ "$queuecount" = "0" ]
	do
		sleep 1
		curl -silent "http://127.0.0.1:8188/prompt" >queuecheck.json
		queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
		if [[ "$lastcount" != "$queuecount" ]] && [[ -n "$lastcount" ]]
		then
			end=`date +%s`
			runtime=$((end-start))
			start=`date +%s`
			secs=$(("$queuecount * runtime"))
			eta=`printf '%02d:%02d:%02s\n' $((secs/3600)) $((secs%3600/60)) $((secs%60))`
			itertimemsg=", $runtime""s/prompt, ETA: $eta"
		fi
		lastcount="$queuecount"
		
		echo -ne "queuecount: $queuecount $itertimemsg         \r"
	done
	runtime=$((end-startjob))
	echo "done. duration: $runtime""s.                      "
	rm queuecheck.json
	echo "Calling $DUBBINGDIR/concat.sh"
	#$DUBBINGDIR/concat.sh

	mkdir -p input/dubbing_in/done
	#mv "$INPUT" input/dubbing_in/done

exit
	echo "" >list.txt
	for i in *.flac; do
		"$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y  -ss 0 -i $i -af "afade=type=in:start_time=0:duration=1,afade=type=out:start_time=$FADEOUTSTART:duration=1" -c:a libmp3lame faded.flac
		mv faded.flac $i
		echo "file $i">>list.txt
	done

	nice "$FFMPEGPATH"ffmpeg.exe -hide_banner -loglevel error -y -f concat -safe 0 -i list.txt output.mp3
	

ffmpeg -ss 0 -hide_banner -loglevel error -y -i sbssegment_00002_.flac -af "afade=type=in:start_time=0:duration=1" -c:a flac fadedin.flac
ffmpeg -ss 0 -hide_banner -loglevel error -y -i sbssegment_00002_.flac -af "afade=type=out:start_time=$FADEOUTSTART:duration=1" -c:a flac fadedout.flac

ffmpeg.exe -hide_banner -loglevel error -y -i sbssegment_00004_.flac -vf fade=in:0:d=1,fade=out:st=$FADEOUTSTART:d=2 -af afade=in:0:d=1,afade=out:st=$FADEOUTSTART:d=2 -c:a flac fadedinout.flac

	
fi

