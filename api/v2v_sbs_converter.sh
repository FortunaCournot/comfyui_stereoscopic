#!/bin/sh
#
# v2v_sbs_converter.sh
#
# Creates SBS video from a base video (input) and places result under ComfyUI/output/sbs folder.
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


# either start this script in ComfyUI folder or enter absolute path of ComfyUI folder in your ComfyUI_windows_portable here
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# API relative to COMFYUIPATH, or absolute path:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/python/v2v_sbs_converter.py
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

	CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

	export CONFIGFILE
	if [ -e $CONFIGFILE ] ; then
		loglevel=$(awk -F "=" '/loglevel/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
		[ $loglevel -ge 2 ] && set -x
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

	depth_scale="$1"
	shift
	depth_offset="$1"
	shift
	INPUT="$1"
	shift

	DEPTH_MODEL_CKPT=$(awk -F "=" '/DEPTH_MODEL_CKPT/ {print $2}' $CONFIGFILE) ; DEPTH_MODEL_CKPT=${DEPTH_MODEL_CKPT:-"depth_anything_v2_vitl.pth"}
	VIDEO_FORMAT=$(awk -F "=" '/VIDEO_FORMAT/ {print $2}' $CONFIGFILE) ; VIDEO_FORMAT=${VIDEO_FORMAT:-"video/h264-mp4"}
	VIDEO_PIXFMT=$(awk -F "=" '/VIDEO_PIXFMT/ {print $2}' $CONFIGFILE) ; VIDEO_PIXFMT=${VIDEO_PIXFMT:-"yuv420p"}
	VIDEO_CRF=$(awk -F "=" '/VIDEO_CRF/ {print $2}' $CONFIGFILE) ; VIDEO_CRF=${VIDEO_CRF:-"17"}

	# some advertising ;-)
	SETMETADATA="-metadata description=\"Created with Side-By-Side Converter: https://civitai.com/models/1757677\" -movflags +use_metadata_tags -metadata depth_scale=\"$depth_scale\" -metadata depth_offset=\"$depth_offset\""

	PROGRESS=" "
	if [ -e input/vr/fullsbs/BATCHPROGRESS.TXT ]
	then
		PROGRESS=`cat input/vr/fullsbs/BATCHPROGRESS.TXT`" "
	fi
	regex="[^/]*$"
	echo "========== $PROGRESS""convert sbs "`echo $INPUT | grep -oP "$regex"`" =========="

	uuid=$(openssl rand -hex 16)
	TARGETPREFIX=${INPUT##*/}
	INPUT=`realpath "$INPUT"`
	TARGETPREFIX=output/vr/fullsbs/intermediate/${TARGETPREFIX%.*}
	TARGETPREFIX="$TARGETPREFIX""_SBS_LR"
	FINALTARGETFOLDER=`realpath "output/vr/fullsbs"`
	mkdir -p "$TARGETPREFIX""-$uuid"".tmpseg"
	mkdir -p "$TARGETPREFIX"".tmpsbs"
	SEGDIR=`realpath "$TARGETPREFIX""-$uuid"".tmpseg"`
	SBSDIR=`realpath "$TARGETPREFIX"".tmpsbs"`
	if [ ! -e "$SBSDIR/concat.sh" ]
	then
		touch "$TARGETPREFIX"".tmpsbs"/x
		touch "$TARGETPREFIX""-$uuid"".tmpseg"/x
		rm "$TARGETPREFIX""-$uuid"".tmpseg"/* "$TARGETPREFIX"".tmpsbs"/*
	fi
	touch $TARGETPREFIX
	TARGETPREFIX=`realpath "$TARGETPREFIX"`
	echo "Converting to SBS from $TARGETPREFIX"
	rm "$TARGETPREFIX"

	SPLITINPUT="$INPUT"
	EXTENSION="${INPUT##*.}"
	if [[ "$EXTENSION" == "webm" ]] || [[ "$EXTENSION" == "WEBM" ]] ; then
		echo "handling unsupported image format"
		NEWTARGET="${SPLITINPUT%.*}"".mp4"
		nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y  -i "$SPLITINPUT" "$NEWTARGET"
		SPLITINPUT=$NEWTARGET
		mv -- $SPLITINPUT $SEGDIR
		SPLITINPUT="$SEGDIR/"`basename $SPLITINPUT`		
	fi

	if [ ! -e "$SBSDIR/concat.sh" ]
	then
		
		# Prepare to restrict resolution to 4K, and skip low res
		if test `"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $SPLITINPUT` -lt 128 -o `"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $SPLITINPUT` -lt  128
		then
			echo "Skipping low resolution video: $SPLITINPUT"
		elif test `"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $SPLITINPUT` -gt 3840 -a `"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $SPLITINPUT` -gt  2160
		then 
			echo "H-Resolution > 4K: Downscaling..."
			$(dirname "$0")/v2v_limit4K.sh "$SPLITINPUT"
			SPLITINPUT="${SPLITINPUT%.mp4}_4K"".mp4"
			mv -- $SPLITINPUT $SEGDIR
			SPLITINPUT="$SEGDIR/"`basename $SPLITINPUT`
		elif test `"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $SPLITINPUT` -gt 2160 -a `"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $SPLITINPUT` -gt  3840
		then 
			echo "V-Resolution > 4K: Downscaling..."
			$(dirname "$0")/v2v_limit4K.sh "$SPLITINPUT"
			SPLITINPUT="${SPLITINPUT%.mp4}_4K"".mp4"
			mv -- $SPLITINPUT $SEGDIR
			SPLITINPUT="$SEGDIR/"`basename $SPLITINPUT`
		fi

		# Prepare to restrict fps
		MAXFPS=$(awk -F "=" '/MAXFPS/ {print $2}' $CONFIGFILE) ; MAXFPS=${MAXFPS:-"30"}
		fpsv=`"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=nw=1:nk=1 $SPLITINPUT`
		fps=$(($fpsv))
		echo "Source FPS: $fps ($fpsv)"
		FPSOPTION=`echo $fps $MAXFPS | awk '{if ($1 > $2) print "-filter:v fps=fps=$MAXFPS" }'`
		if [[ -n "$FPSOPTION" ]]
		then 
			SPLITINPUTFPS="$SEGDIR/splitinput_fps.mp4"
			echo "Rencoding to $MAXFPS fps ..."
			nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i "$SPLITINPUT" -filter:v fps=fps=$MAXFPS "$SPLITINPUTFPS"
			SPLITINPUT="$SPLITINPUTFPS"
		fi
	else
		until [ "$queuecount" = "0" ]
		do
			sleep 1
			curl -silent "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json
			queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
			echo -ne "Waiting for old queue to finish. queuecount: $queuecount         \r"
		done
		echo "recovering...                                                             "
		queuecount=
	fi
	
	TESTAUDIO=`"$FFMPEGPATHPREFIX"ffprobe -i "$SPLITINPUT" -show_streams -select_streams a -loglevel error`
	AUDIOMAPOPT="-map 0:a:0"
	if [[ ! $TESTAUDIO =~ "[STREAM]" ]]; then
		AUDIOMAPOPT=""
	fi
	if [ ! -e "$SBSDIR/concat.sh" ]
	then
		echo "Splitting into segments"
		nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i "$SPLITINPUT" -c:v libx264 -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" -crf 17 -map 0:v:0 $AUDIOMAPOPT -segment_time 1 -g 9 -sc_threshold 0 -force_key_frames "expr:gte(t,n_forced*9)" -f segment -segment_start_number 1 -max_muxing_queue_size 9999 "$SEGDIR/segment%05d.mp4"
		# -max_muxing_queue_size 9999 
		if [ ! -e "$SEGDIR/segment00001.mp4" ]; then
			echo -e $"\e[91mError:\e[0m No segments!"
			exit
		fi
	fi
	echo "Prompting ..."
	for f in "$SEGDIR"/segment*.mp4 ; do
		f2=${f%.mp4}
		f2=${f2#$SEGDIR/segment}
		echo -ne "$f2...       \r"
		if [ ! -e "$SBSDIR/sbssegment_$f2.mp4" ]
		then
			if [[ ! $TESTAUDIO =~ "[STREAM]" ]]; then
				# create audio
				mv "$f" "${f%.mp4}_na.mp4"
				nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 -i "${f%.mp4}_na.mp4" -y -f ffmetadata metadata.txt -c:v copy -c:a aac -shortest "$f"
				rm -f "${f%.mp4}_na.mp4"
			fi
			status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
			if [ "$status" = "closed" ]; then
				echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
				exit
			fi
			echo -ne $"\e[91m" ; "$PYTHON_BIN_PATH"python.exe $SCRIPTPATH "$DEPTH_MODEL_CKPT" $depth_scale $depth_offset "$f" "$SBSDIR"/sbssegment "$VIDEO_FORMAT" "$VIDEO_PIXFMT" "$VIDEO_CRF" ; echo -ne $"\e[0m"
		fi
	done
	echo "Jobs running...   "
	
	echo "#!/bin/sh" >"$SBSDIR/concat.sh"
	echo "cd \"\$(dirname \"\$0\")\"" >>"$SBSDIR/concat.sh"
	echo "FPSOPTION=\"$FPSOPTION\"" >>"$SBSDIR/concat.sh"
	echo "rm -rf \"$SEGDIR\"" >>"$SBSDIR/concat.sh"
	echo "if [ -e ./sbssegment_00001-audio.mp4 ]" >>"$SBSDIR/concat.sh"
	echo "then" >>"$SBSDIR/concat.sh"
	echo "    list=\`find . -type f -print | grep mp4 | grep -v audio\`" >>"$SBSDIR/concat.sh"
	echo "    rm \$list" >>"$SBSDIR/concat.sh"
	echo "fi" >>"$SBSDIR/concat.sh"
	echo "for f in ./*.mp4 ; do" >>"$SBSDIR/concat.sh"
	echo "	echo \"file \$f\" >> "$SBSDIR"/list.txt" >>"$SBSDIR/concat.sh"
	echo "done" >>"$SBSDIR/concat.sh"
	echo "$FFMPEGPATHPREFIX""ffprobe -i $INPUT -show_streams -select_streams a -loglevel error >TESTAUDIO.txt 2>&1"  >>"$SBSDIR/concat.sh"
	echo "TESTAUDIO=\`cat TESTAUDIO.txt\`"  >>"$SBSDIR/concat.sh"
	echo "if [[ \"\$TESTAUDIO\" =~ \"[STREAM]\" ]]; then" >>"$SBSDIR/concat.sh"
	echo "    nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i list.txt -c copy -max_muxing_queue_size 9999 output.mp4" >>"$SBSDIR/concat.sh"
	echo "    nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i output.mp4 -i $INPUT -c copy -map 0:v:0 -map 1:a:0 -max_muxing_queue_size 9999 output2.mp4" >>"$SBSDIR/concat.sh"
	echo "    nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i output2.mp4 -i sbssegment_00001.png -map 1 -map 0 -c copy -disposition:0 attached_pic -max_muxing_queue_size 9999 output3.mp4" >>"$SBSDIR/concat.sh"
	echo "    nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i output3.mp4 $SETMETADATA -vcodec libx264 -x264opts \"frame-packing=3\" -force_key_frames \"expr:gte(t,n_forced*1)\" -max_muxing_queue_size 9999 $TARGETPREFIX"".mp4" >>"$SBSDIR/concat.sh"
	echo "else" >>"$SBSDIR/concat.sh"
	echo "    nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i list.txt -c copy output2.mp4" >>"$SBSDIR/concat.sh"
	echo "    nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i output2.mp4 -i sbssegment_00001.png -map 1 -map 0 -c copy -disposition:0 attached_pic -max_muxing_queue_size 9999 output3.mp4" >>"$SBSDIR/concat.sh"
	echo "    nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i output3.mp4 $SETMETADATA -vcodec libx264 -x264opts \"frame-packing=3\" -force_key_frames \"expr:gte(t,n_forced*1)\" -max_muxing_queue_size 9999 $TARGETPREFIX"".mp4" >>"$SBSDIR/concat.sh"
	echo "fi" >>"$SBSDIR/concat.sh"
	echo "if [ -e $TARGETPREFIX"".mp4 ]" >>"$SBSDIR/concat.sh"
	echo "then" >>"$SBSDIR/concat.sh"
	echo "    mkdir -p $FINALTARGETFOLDER" >>"$SBSDIR/concat.sh"
	echo "    mv -- $TARGETPREFIX"".mp4"" $FINALTARGETFOLDER" >>"$SBSDIR/concat.sh"
	echo "    cd .." >>"$SBSDIR/concat.sh"
	echo "    rm -rf \"$TARGETPREFIX\"\".tmpsbs\"" >>"$SBSDIR/concat.sh"
	echo "    echo -e \$\"\\e[92mdone.\\e[0m\"" >>"$SBSDIR/concat.sh"
	echo "else" >>"$SBSDIR/concat.sh"
	echo "    echo -e \$\"\\e[91mError\\e[0m: Concat failed.\"" >>"$SBSDIR/concat.sh"
	echo "    exit -1" >>"$SBSDIR/concat.sh"
	echo "fi" >>"$SBSDIR/concat.sh"
	echo "Waiting for queue to finish..."
	sleep 4  # Give some extra time to start...
	lastcount=""
	start=`date +%s`
	end=`date +%s`
	startjob=$start
	itertimemsg=""
	until [ "$queuecount" = "0" ]
	do
		sleep 1
		curl -silent "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json
		queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
		if [[ -z "$queuecount" ]]; then
			echo -ne $"\e[91mError:\e[0m Lost connection to ComfyUI. STOPPED PROCESSING.                     "
			exit
		fi
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
	echo "done. duration: $runtime""s.                         "
	rm queuecheck.json
	echo "Calling $SBSDIR/concat.sh"
	$SBSDIR/concat.sh
	mkdir -p input/vr/fullsbs/done
	mv -fv "$INPUT" input/vr/fullsbs/done
	
fi

