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
# Use Systempath for python by default, but set it explictly for comfyui portable.
PYTHON_BIN_PATH=
if [ -d "../python_embeded" ]; then
  PYTHON_BIN_PATH=../python_embeded/
fi

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

	SETMETADATA="-metadata description=\"Created with Side-By-Side Converter: https://civitai.com/models/1757677\" -movflags +use_metadata_tags -metadata depth_scale=\"$depth_scale\" -metadata depth_offset=\"$depth_offset\""

	PROGRESS=" "
	if [ -e input/sbs_in/BATCHPROGRESS.TXT ]
	then
		PROGRESS=`cat input/sbs_in/BATCHPROGRESS.TXT`" "
	fi
	regex="[^/]*$"
	echo "========== $PROGRESS""convert "`echo $INPUT | grep -oP "$regex"`" =========="
	
	TARGETPREFIX=${INPUT##*/}
	INPUT=`realpath "$INPUT"`
	TARGETPREFIX=output/fullsbs/${TARGETPREFIX%.mp4}
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

	SPLITINPUT="$INPUT"
	
	# Prepare to restrict resolution to 4K
	if test `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $INPUT` -gt 3840 -a `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $INPUT` -gt  2160
	then 
		echo "H-Resolution > 4K: Downscaling..."
		$(dirname "$0")/v2v_limit4K.sh "$SPLITINPUT"
		SPLITINPUT="${SPLITINPUT%.mp4}_4K"".mp4"
		mv $SPLITINPUT $SEGDIR
		SPLITINPUT="$SEGDIR/"`basename $SPLITINPUT`
	elif test `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $INPUT` -gt 2160 -a `"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $INPUT` -gt  3840
	then 
		echo "V-Resolution > 4K: Downscaling..."
		$(dirname "$0")/v2v_limit4K.sh "$SPLITINPUT"
		SPLITINPUT="${SPLITINPUT%.mp4}_4K"".mp4"
		mv $SPLITINPUT $SEGDIR
		SPLITINPUT="$SEGDIR/"`basename $SPLITINPUT`
	fi

	# Prepare to restrict fps
	fpsv=`"$FFMPEGPATH"ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=nw=1:nk=1 $SPLITINPUT`
	fps=$(($fpsv))
	echo "Source FPS: $fps ($fpsv)"
	FPSOPTION=`echo $fps 30.0 | awk '{if ($1 > $2) print "-filter:v fps=fps=30" }'`
	if [[ -n "$FPSOPTION" ]]
	then 
		SPLITINPUTFPS30="$SEGDIR/splitinput_fps30.mp4"
		echo "Rencoding to 30.0 ..."
		nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i "$SPLITINPUT" -filter:v fps=fps=30 "$SPLITINPUTFPS30"
		SPLITINPUT="$SPLITINPUTFPS30"
	fi
	
	echo "Splitting into segments and prompting ..."
	TESTAUDIO=`ffprobe -i "$SPLITINPUT" -show_streams -select_streams a -loglevel error`
	AUDIOMAPOPT="-map 0:a:0"
	if [[ ! $TESTAUDIO =~ "[STREAM]" ]]; then
		AUDIOMAPOPT=""
	fi
	nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -i "$SPLITINPUT" -c:v libx264 -crf 22 -map 0:v:0 $AUDIOMAPOPT -segment_time 1 -g 9 -sc_threshold 0 -force_key_frames "expr:gte(t,n_forced*9)" -f segment "$SEGDIR/segment%05d.mp4"
	for f in "$SEGDIR"/segment*.mp4 ; do
		if [[ ! $TESTAUDIO =~ "[STREAM]" ]]; then
			# create audio
			mv "$f" "${f%.mp4}_na.mp4"
			nice ffmpeg -hide_banner -loglevel error -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 -i "${f%.mp4}_na.mp4" -y -f ffmetadata metadata.txt -c:v copy -c:a aac -shortest "$f"
		fi
		"$PYTHON_BIN_PATH"python.exe $SCRIPTPATH $depth_scale $depth_offset "$f" "$SBSDIR"/sbssegment
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
	echo "    nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i output3.mp4 $SETMETADATA -vcodec libx264 -x264opts \"frame-packing=3\" $TARGETPREFIX"".mp4" >>"$SBSDIR/concat.sh"
	echo "else" >>"$SBSDIR/concat.sh"
	echo "    nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i list.txt -c copy output2.mp4" >>"$SBSDIR/concat.sh"
	echo "    nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i output2.mp4 -i sbssegment_00001.png -map 1 -map 0 -c copy -disposition:0 attached_pic output3.mp4" >>"$SBSDIR/concat.sh"
	echo "    nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -i output3.mp4 $SETMETADATA -vcodec libx264 -x264opts \"frame-packing=3\" $TARGETPREFIX"".mp4" >>"$SBSDIR/concat.sh"
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
	echo "Calling $SBSDIR/concat.sh"
	$SBSDIR/concat.sh
	
fi

