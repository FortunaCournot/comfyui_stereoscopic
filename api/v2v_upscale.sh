#!/bin/sh
#
# v2v_upscale.sh
#
# Upscales a base video (input) by Real-ESRGAN-x4plus and places result under ComfyUI/output/upscale folder.
# The end condition must be checked manually in ComfyUI Frontend (Browser). If queue is empty the concat script (path is logged) can be called. 
#
# Copyright (c) 2025 FortunaCournot. MIT License.

# ComfyUI API script needs the following custom node packages: 
#  comfyui-videohelpersuite, bjornulf_custom_nodes, comfyui-easy-use, comfyui-custom-scripts, ComfyLiterals

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).
# Prerequisite: Configured path variables below.
# Prerequisite: Git Bash installed. Call this script in Git Bash

# - It will split the input video into segements,
# - It queues upscale conversion workflows via api,
# - Creates a shell script for concating resulting sbs segments
# - Wait until comfyui is done, then call created script manually.

# set FFMPEGPATH if ffmpeg binary is not in your enviroment path
FFMPEGPATH=
# either start this script in ComfyUI folder or enter absolute path of ComfyUI folder in your ComfyUI_windows_portable here
COMFYUIPATH=.
# API relative to COMFYUIPATH, or absolute path:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/v2v_upscale.py

if test $# -ne 1 -a $# -ne 2
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 input [sigma]"
    echo "E.g.: $0 SmallIconicTown.mp4 3.0"
else
	cd $COMFYUIPATH

	SIGMA=1.0
	INPUT="$1"
	shift
	
	PROGRESS=" "
	if [ -e input/upscale_in/BATCHPROGRESS.TXT ]
	then
		PROGRESS=`cat input/upscale_in/BATCHPROGRESS.TXT`" "
	fi
	echo "========== $PROGRESS""rescale $INPUT =========="
	
	if test $# -eq 1
	then
		SIGMA=$1
		shift	
	fi
	TARGETPREFIX=${INPUT##*/}
	INPUT=`realpath "$INPUT"`
	TARGETPREFIX=output/upscale/${TARGETPREFIX%.mp4}
	UPSCALEMODEL=RealESRGAN_x2.pth
	if test `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $INPUT` -le 1920 -a `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $INPUT` -le  1080
	then 
		TARGETPREFIX="$TARGETPREFIX""_x2"
		if test `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $INPUT` -le 960 -a `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $INPUT` -le  540
		then 
			UPSCALEMODEL=RealESRGAN_x4plus.pth
			TARGETPREFIX="$TARGETPREFIX""_x4"
		fi
	fi
	
	if test `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $INPUT` -le 1920 -a `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $INPUT` -le  1080
	then 
		mkdir -p "$TARGETPREFIX"".tmpseg"
		mkdir -p "$TARGETPREFIX"".tmpupscale"
		touch "$TARGETPREFIX"".tmpseg"/x
		touch "$TARGETPREFIX"".tmpupscale"/x
		rm "$TARGETPREFIX"".tmpseg"/* "$TARGETPREFIX"".tmpupscale"/*
		SEGDIR=`realpath "$TARGETPREFIX"".tmpseg"`
		UPSCALEDIR=`realpath "$TARGETPREFIX"".tmpupscale"`
		touch $TARGETPREFIX
		TARGETPREFIX=`realpath "$TARGETPREFIX"`
		echo "prompting for $TARGETPREFIX"
		rm "$TARGETPREFIX"
		
		echo "Splitting into segments and prompting ..."
		nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -i "$INPUT" -c:v libx264 -crf 22 -map 0 -segment_time 1 -g 9 -sc_threshold 0 -force_key_frames "expr:gte(t,n_forced*9)" -f segment "$SEGDIR/segment%05d.mp4"
		for f in "$SEGDIR"/*.mp4 ; do
			TESTAUDIO=`ffprobe -i "$f" -show_streams -select_streams a -loglevel error`
			if [[ ! $TESTAUDIO =~ "[STREAM]" ]]; then
				mv "$f" "${f%.mp4}_na.mp4"
				nice ffmpeg -hide_banner -loglevel error -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 -i "${f%.mp4}_na.mp4" -y -f ffmetadata metadata.txt -c:v copy -c:a aac -shortest "$f"
			fi
			../python_embeded/python.exe $SCRIPTPATH "$f" "$UPSCALEDIR"/sbssegment $UPSCALEMODEL $SIGMA
		done
		
		echo "#!/bin/sh" >"$UPSCALEDIR/concat.sh"
		echo "cd \"\$(dirname \"\$0\")\"" >>"$UPSCALEDIR/concat.sh"
		echo "rm -rf \"$TARGETPREFIX\"\".tmpseg\"" >>"$UPSCALEDIR/concat.sh"
		echo "if [ -e ./sbssegment_00001-audio.mp4 ]" >>"$UPSCALEDIR/concat.sh"
		echo "then" >>"$UPSCALEDIR/concat.sh"
		echo "    list=\`find . -type f -print | grep mp4 | grep -v audio\`" >>"$UPSCALEDIR/concat.sh"
		echo "    rm \$list" >>"$UPSCALEDIR/concat.sh"
		echo "fi" >>"$UPSCALEDIR/concat.sh"
		echo "for f in ./*.mp4 ; do" >>"$UPSCALEDIR/concat.sh"
		echo "	echo \"file \$f\" >> "$UPSCALEDIR"/list.txt" >>"$UPSCALEDIR/concat.sh"
		echo "done" >>"$UPSCALEDIR/concat.sh"
		echo "$FFMPEGPATH""ffprobe -i $INPUT -show_streams -select_streams a -loglevel error >TESTAUDIO.txt 2>&1"  >>"$UPSCALEDIR/concat.sh"
		echo "TESTAUDIO=\`cat TESTAUDIO.txt\`"  >>"$UPSCALEDIR/concat.sh"
		echo "if [[ \"\$TESTAUDIO\" =~ \"[STREAM]\" ]]; then" >>"$UPSCALEDIR/concat.sh"
		echo "    nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i list.txt -c copy output.mp4" >>"$UPSCALEDIR/concat.sh"
		echo "    nice "$FFMPEGPATH"ffmpeg -i output.mp4 -i $INPUT -c copy -map 0:v:0 -map 1:a:0 $TARGETPREFIX"".mp4" >>"$UPSCALEDIR/concat.sh"
		echo "else" >>"$UPSCALEDIR/concat.sh"
		echo "    nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i list.txt -c copy $TARGETPREFIX"".mp4" >>"$UPSCALEDIR/concat.sh"
		echo "fi" >>"$UPSCALEDIR/concat.sh"
		echo "cd .." >>"$UPSCALEDIR/concat.sh"
		echo "rm -rf \"$TARGETPREFIX\"\".tmpupscale\"" >>"$UPSCALEDIR/concat.sh"
		echo "echo done." >>"$UPSCALEDIR/concat.sh"
		#echo "Wait until comfyui tasks are done (check ComfyUI queue in browser), then call the script manually: $UPSCALEDIR/concat.sh"
		
		echo "Waiting for queue to finish..."
		sleep 4  # Give some extra time to start...
		queuecount=""
		until [ "$queuecount" = "0" ]
		do
			sleep 1
			curl -silent "http://127.0.0.1:8188/prompt" >queuecheck.json
			queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
			echo -ne "queuecount: $queuecount  \r"
		done
		echo -ne '\ndone.'
		rm queuecheck.json
		echo "Calling $UPSCALEDIR/concat.sh"
		$UPSCALEDIR/concat.sh
		
	else
		echo "Skipping upscaling of large video $INPUT"
		cp $INPUT "$TARGETPREFIX"".mp4"
	fi
fi

