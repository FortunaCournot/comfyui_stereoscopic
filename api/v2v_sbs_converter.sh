#!/bin/sh
#
# v2v_sbs_converter.sh
#
# Creates SBS video from a base video (input) and places result under ComfyUI/output/sbs folder.
# The end condition must be checked manually in ComfyUI Frontend (Browser). If queue is empty the concat script (path is logged) can be called. 
#
# Copyright (c) 2025 FortunaCournot. MIT License.

# ComfyUI API script needs the following custom node packages: 
#  comfyui_stereoscopic, comfyui_controlnet_aux, comfyui-videohelpersuite, bjornulf_custom_nodes, comfyui-easy-use, comfyui-custom-scripts, ComfyLiterals

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).
# Prerequisite: Configured path variables below.
# Prerequisite: Git Bash installed. Call this script in Git Bash

# - It will split the input video into segements,
# - It queues sbs conversion workflows via api,
# - Creates a shell script for concating resulting sbs segments
# - Wait until comfyui is done, then call created script manually.

# set FFMPEGPATH if ffmpeg binary is not in your enviroment path
FFMPEGPATH=
# either start this script in ComfyUI folder or enter absolute path of ComfyUI folder in your ComfyUI_windows_portable here
COMFYUIPATH=.
# API relative to COMFYUIPATH, or absolute path:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/v2v_sbs_converter.py

if test $# -ne 3
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 depth_scale depth_offset input"
    echo "E.g.: $0 1.0 0.0 SmallIconicTown.mp4"
else

	cd $COMFYUIPATH

	depth_scale="$1"
	shift
	depth_offset="$1"
	shift
	INPUT="$1"
	shift

	PROGRESS=" "
	if [ -e input/sbs_in/BATCHPROGRESS.TXT ]
	then
		PROGRESS=`cat input/sbs_in/BATCHPROGRESS.TXT`" "
	fi
	regex="[^/]*$"
	echo "========== $PROGRESS""convert "`echo $INPUT | grep -oP "$regex"`" =========="
	
	TARGETPREFIX=${INPUT##*/}
	INPUT=`realpath "$INPUT"`
	TARGETPREFIX=output/sbs/${TARGETPREFIX%.mp4}
	TARGETPREFIX="$TARGETPREFIX""_SBS_LR"
	mkdir -p "$TARGETPREFIX"".tmpseg"
	mkdir -p "$TARGETPREFIX"".tmpsbs"
	touch "$TARGETPREFIX"".tmpsbs"/x
	touch "$TARGETPREFIX"".tmpseg"/x
	rm "$TARGETPREFIX"".tmpseg"/* "$TARGETPREFIX"".tmpsbs"/*
	SEGDIR=`realpath "$TARGETPREFIX"".tmpseg"`
	SBSDIR=`realpath "$TARGETPREFIX"".tmpsbs"`
	touch $TARGETPREFIX
	TARGETPREFIX=`realpath "$TARGETPREFIX"`
	echo "Converting to SBS from $TARGETPREFIX"
	rm "$TARGETPREFIX"
	
	# Prepare to restrict fps
	fpsv=`"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=nw=1:nk=1 $INPUT`
	fps=$(($fpsv))
	echo "Source FPS: $fps ($fpsv)"
	SPLITINPUT="$INPUT"
	FPSOPTION=""
	echo $fps 30.0 | awk '{if ($1 > $2) FPSOPTION="-filter:v fps=fps=30" }'
	if [[ -n "$FPSOPTION" ]]
	then 
		SPLITINPUT="$SEGDIR/splitinput_fps30.mp4"
		echo "Rencoding to 30.0 ..."
		nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -i "$INPUT" -filter:v fps=fps=30 "$SPLITINPUT"
	fi
	
	echo "Splitting into segments and prompting ..."
	nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -i "$SPLITINPUT" -c:v libx264 -crf 22 -map 0:v:0 -map 0:a:0  -segment_time 1 -g 9 -sc_threshold 0 -force_key_frames "expr:gte(t,n_forced*9)" -f segment "$SEGDIR/segment%05d.mp4"
	for f in "$SEGDIR"/*.mp4 ; do
		TESTAUDIO=`ffprobe -i "$f" -show_streams -select_streams a -loglevel error`
		if [[ ! $TESTAUDIO =~ "[STREAM]" ]]; then
			mv "$f" "${f%.mp4}_na.mp4"
			nice ffmpeg -hide_banner -loglevel error -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 -i "${f%.mp4}_na.mp4" -y -f ffmetadata metadata.txt -c:v copy -c:a aac -shortest "$f"
		fi
		../python_embeded/python.exe $SCRIPTPATH $depth_scale $depth_offset "$f" "$SBSDIR"/sbssegment
	done
	
	echo "#!/bin/sh" >"$SBSDIR/concat.sh"
	echo "cd \"\$(dirname \"\$0\")\"" >>"$SBSDIR/concat.sh"
	echo "FPSOPTION=\"$FPSOPTION\"" >>"$SBSDIR/concat.sh"
	echo "rm -rf \"$TARGETPREFIX\"\".tmpseg\"" >>"$SBSDIR/concat.sh"
	echo "if [ -e ./sbssegment_00001-audio.mp4 ]" >>"$SBSDIR/concat.sh"
	echo "then" >>"$SBSDIR/concat.sh"
	echo "    list=\`find . -type f -print | grep mp4 | grep -v audio\`" >>"$SBSDIR/concat.sh"
	echo "    rm \$list" >>"$SBSDIR/concat.sh"
	echo "fi" >>"$SBSDIR/concat.sh"
	echo "for f in ./*.mp4 ; do" >>"$SBSDIR/concat.sh"
	echo "	echo \"file \$f\" >> "$SBSDIR"/list.txt" >>"$SBSDIR/concat.sh"
	echo "done" >>"$SBSDIR/concat.sh"
	echo "$FFMPEGPATH""ffprobe -i $INPUT -show_streams -select_streams a -loglevel error >TESTAUDIO.txt 2>&1"  >>"$SBSDIR/concat.sh"
	echo "TESTAUDIO=\`cat TESTAUDIO.txt\`"  >>"$SBSDIR/concat.sh"
	echo "if [[ \"\$TESTAUDIO\" =~ \"[STREAM]\" ]]; then" >>"$SBSDIR/concat.sh"
	echo "    nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i list.txt -c copy output.mp4" >>"$SBSDIR/concat.sh"
	echo "    nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i output.mp4 -i $INPUT -c copy -map 0:v:0 -map 1:a:0 output2.mp4" >>"$SBSDIR/concat.sh"
	echo "    nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i output2.mp4 -i sbssegment_00001.png -map 1 -map 0 -c copy -disposition:0 attached_pic output3.mp4" >>"$SBSDIR/concat.sh"
	echo "    nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i output3.mp4 -vcodec libx264 -x264opts \"frame-packing=3\" $TARGETPREFIX"".mp4" >>"$SBSDIR/concat.sh"
	echo "else" >>"$SBSDIR/concat.sh"
	echo "    nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i list.txt -c copy output2.mp4" >>"$SBSDIR/concat.sh"
	echo "    nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i output2.mp4 -i sbssegment_00001.png -map 1 -map 0 -c copy -disposition:0 attached_pic output3.mp4" >>"$SBSDIR/concat.sh"
	echo "    nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i output3.mp4 -vcodec libx264 -x264opts \"frame-packing=3\" $TARGETPREFIX"".mp4" >>"$SBSDIR/concat.sh"
	echo "fi" >>"$SBSDIR/concat.sh"
	echo "cd .." >>"$SBSDIR/concat.sh"
	echo "rm -rf \"$TARGETPREFIX\"\".tmpsbs\"" >>"$SBSDIR/concat.sh"
	echo "echo done." >>"$SBSDIR/concat.sh"

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
			eta=$(("$queuecount * runtime"))
			itertimemsg=", $runtime""s/prompt, ETA: $eta""s"
		fi
		lastcount="$queuecount"
			
		echo -ne "queuecount: $queuecount $itertimemsg     \r"
	done
	runtime=$((end-startjob))
	echo "done. duration: $runtime""s.                  "
	rm queuecheck.json
	echo "Calling $SBSDIR/concat.sh"
	$SBSDIR/concat.sh
	
fi

