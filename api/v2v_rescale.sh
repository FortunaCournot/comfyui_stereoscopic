#!/bin/sh
#
# v2v_rescale.sh
#
# Scales a base video (input) down by factor 4 and than up by Real-ESRGAN-x4plus and places result under ComfyUI/output/vr/scaling folder.
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

# either start this script in ComfyUI folder or enter absolute path of ComfyUI folder in your ComfyUI_windows_portable here
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# Use Systempath for python by default, but set it explictly for comfyui portable.
PYTHON_BIN_PATH=
if [ -d "../python_embeded" ]; then
  PYTHON_BIN_PATH=../python_embeded/
fi

if test $# -ne 1 -a $# -ne 2
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 input [sigma]"
    echo "E.g.: $0 SmallIconicTown.mp4 0.2"
fi

if test $# -eq 1 -o $# -eq 2
then
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

	# set FFMPEGPATHPREFIX if ffmpeg binary is not in your enviroment path
	FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}

	SIGMA=0.2
	INPUT="$1"
	shift
	
	PROGRESS=" "
	if [ -e input/vr/scaling/BATCHPROGRESS.TXT ]
	then
		PROGRESS=`cat input/vr/scaling/BATCHPROGRESS.TXT`" "
	fi
	regex="[^/]*$"
	echo "========== $PROGRESS""rescale "`echo $INPUT | grep -oP "$regex"`" =========="
	
	if test $# -eq 1
	then
		SIGMA=$1
		shift	
	fi
	TARGETPREFIX=${INPUT##*/}
	INPUT=`realpath "$INPUT"`
	TARGETPREFIX=output/vr/scaling/intermediate/${TARGETPREFIX%.mp4}
	FINALTARGETFOLDER=`realpath "output/vr/scaling"`
	TARGETPREFIX="$TARGETPREFIX""_x1"
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
	TESTAUDIO=`ffprobe -i "$INPUT" -show_streams -select_streams a -loglevel error`
	AUDIOMAPOPT="-map 0:a:0"
	if [[ ! $TESTAUDIO =~ "[STREAM]" ]]; then
		AUDIOMAPOPT=""
	fi
	nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -i "$INPUT" -c:v libx264 -crf 17 -map 0:v:0 $AUDIOMAPOPT -segment_time 1 -g 9 -sc_threshold 0 -force_key_frames "expr:gte(t,n_forced*9)" -f segment "$SEGDIR/segment%05d.mp4"
	for f in "$SEGDIR"/*.mp4 ; do
		TESTAUDIO=`ffprobe -i "$f" -show_streams -select_streams a -loglevel error`
		if [[ ! $TESTAUDIO =~ "[STREAM]" ]]; then
			mv "$f" "${f%.mp4}_na.mp4"
			nice ffmpeg -hide_banner -loglevel error -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 -i "${f%.mp4}_na.mp4" -y -f ffmetadata metadata.txt -c:v copy -c:a aac -shortest "$f"
		fi
		"$PYTHON_BIN_PATH"python.exe $SCRIPTPATH "$f" "$UPSCALEDIR"/sbssegment $SIGMA
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
	echo "$FFMPEGPATHPREFIX""ffprobe -i $INPUT -show_streams -select_streams a -loglevel error >TESTAUDIO.txt 2>&1"  >>"$UPSCALEDIR/concat.sh"
	echo "TESTAUDIO=\`cat TESTAUDIO.txt\`"  >>"$UPSCALEDIR/concat.sh"
	echo "files=(*.mp4)"  >>"$UPSCALEDIR/concat.sh"
	echo "nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i \${files[0]} -vf \"thumbnail\" -frames:v 1 thumbnail.png" >>"$UPSCALEDIR/concat.sh"
	echo "if [[ \"\$TESTAUDIO\" =~ \"[STREAM]\" ]]; then" >>"$UPSCALEDIR/concat.sh"
	echo "    nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i list.txt -c copy output.mp4" >>"$UPSCALEDIR/concat.sh"
	echo "    nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i output.mp4 -i $INPUT -c copy -map 0:v:0 -map 1:a:0 output2.mp4" >>"$UPSCALEDIR/concat.sh"
	echo "    nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i output2.mp4 -i thumbnail.png -map 1 -map 0 -c copy -disposition:0 attached_pic $TARGETPREFIX"".mp4" >>"$UPSCALEDIR/concat.sh"
	echo "else" >>"$UPSCALEDIR/concat.sh"
	echo "    nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i list.txt -c copy output2.mp4" >>"$UPSCALEDIR/concat.sh"
	echo "    nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i output2.mp4 -i thumbnail.png -map 1 -map 0 -c copy -disposition:0 attached_pic $TARGETPREFIX"".mp4" >>"$UPSCALEDIR/concat.sh"
	echo "fi" >>"$UPSCALEDIR/concat.sh"
	echo "mkdir -p $FINALTARGETFOLDER" >>"$UPSCALEDIR/concat.sh"
	echo "mv $TARGETPREFIX"".mp4"" $FINALTARGETFOLDER" >>"$UPSCALEDIR/concat.sh"
	echo "cd .." >>"$UPSCALEDIR/concat.sh"
	echo "rm -rf \"$TARGETPREFIX\"\".tmpupscale\"" >>"$UPSCALEDIR/concat.sh"
	echo "echo done." >>"$UPSCALEDIR/concat.sh"
	
	echo "Waiting for queue to finish..."
	sleep 4  # Give some extra time to start...
	lastcount=""
	start=`date +%s`
	startjob=$start
	itertimemsg=""
    until [ "$queuecount" = "0" ]
	do
		sleep 1
		curl -silent "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json
		queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
		if [[ "$lastcount" != "$queuecount" ]] && [[ -n "$lastcount" ]]
		then
			end=`date +%s`
			runtime=$((end-start))
			start=`date +%s`
			secs=$(("$queuecount * runtime"))
			eta=`printf '%02d:%02d:%02s\n' $((secs/3600)) $((secs%3600/60)) $((secs%60))`
			itertimemsg=", $runtime""s/prompt, ETA in $eta"
		fi
		lastcount="$queuecount"
			
		echo -ne $"\e[1mqueuecount:\e[0m $queuecount $itertimemsg         \r"
	done
	runtime=$((end-startjob))
	echo "done. duration: $runtime""s.                      "
	rm queuecheck.json
	echo "Calling $UPSCALEDIR/concat.sh"
	$UPSCALEDIR/concat.sh
	mkdir -p input/vr/scaling/done
	mv -fv "$INPUT" input/vr/scaling/done
fi

