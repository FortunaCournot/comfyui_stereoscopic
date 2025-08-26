#!/bin/sh
#
# v2v_interpolate.sh
#
# Creates SBS video from a base video (input) and places result under ComfyUI/output/sbs folder.
#
# Copyright (c) 2025 Fortuna Cournot. MIT License. www.3d-gallery.org

# ComfyUI API script needs the following custom node packages: 
#  comfyui_stereoscopic, comfyui_controlnet_aux, comfyui-videohelpersuite, bjornulf_custom_nodes, comfyui-easy-use, comfyui-custom-scripts, ComfyLiterals

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).
# Prerequisite: Configured path variables below.
# Prerequisite: Git Bash installed. Call this script in Git Bash

# - It will split the input video into segements,
# - It queues sbs conversion workflows via api,
# - Creates a shell script for concating resulting segments
# - Wait until comfyui is done, then call created script manually.


# either start this script in ComfyUI folder or enter absolute path of ComfyUI folder in your ComfyUI_windows_portable here
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# API relative to COMFYUIPATH, or absolute path:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/python/v2v_interpolate.py
# Use Systempath for python by default, but set it explictly for comfyui portable.
PYTHON_BIN_PATH=
if [ -d "../python_embeded" ]; then
  PYTHON_BIN_PATH=../python_embeded/
fi

if test $# -ne 3
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 multiplicator vram_gb input"
    echo "E.g.: $0 2 16 SmallIconicTown.mp4"
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

	EXIFTOOLBINARY=$(awk -F "=" '/EXIFTOOLBINARY/ {print $2}' $CONFIGFILE) ; EXIFTOOLBINARY=${EXIFTOOLBINARY:-""}
	
	# set FFMPEGPATHPREFIX if ffmpeg binary is not in your enviroment path
	FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}

	multiplicator="$1"
	shift
	VRAM="$1"
	shift
	INPUT="$1"
	if [ ! -e "$1" ] ; then echo "input file removed: $INPUT"; exit 0; fi
	shift

	# Notice: At SEGMENTTIME=5 (63 frames 4K) crashes ComfyUI without error
	SEGMENTTIME=1
	
	VIDEO_FORMAT=$(awk -F "=" '/VIDEO_FORMAT/ {print $2}' $CONFIGFILE) ; VIDEO_FORMAT=${VIDEO_FORMAT:-"video/h264-mp4"}
	VIDEO_PIXFMT=$(awk -F "=" '/VIDEO_PIXFMT/ {print $2}' $CONFIGFILE) ; VIDEO_PIXFMT=${VIDEO_PIXFMT:-"yuv420p"}
	VIDEO_CRF=$(awk -F "=" '/VIDEO_CRF/ {print $2}' $CONFIGFILE) ; VIDEO_CRF=${VIDEO_CRF:-"17"}

	CWD=`pwd`
	CWD=`realpath "$CWD"`
	
	# some advertising ;-)
	SETMETADATA="-metadata description=\"Created with Side-By-Side Converter: https://civitai.com/models/1757677\" -movflags +use_metadata_tags -metadata depth_scale=\"$depth_scale\" -metadata depth_offset=\"$depth_offset\""

	PROGRESS=" "
	if [ -e input/vr/interpolate/BATCHPROGRESS.TXT ]
	then
		PROGRESS=`cat input/vr/interpolate/BATCHPROGRESS.TXT`" "
	fi
	regex="[^/]*$"
	echo "========== $PROGRESS""interpolate fps $multiplicator""x "`echo $INPUT | grep -oP "$regex"`" =========="

	PIXELLIMIT=$(( 150000 * VRAM ))
	
	`"$FFMPEGPATHPREFIX"ffprobe -hide_banner -v error -select_streams v:0 -show_entries stream=codec_type,codec_name,bit_rate,width,height,r_frame_rate,duration,nb_frames -of json -i "$INPUT" >output/vr/interpolate/intermediate/probe.txt`
	
	temp=`grep width output/vr/interpolate/intermediate/probe.txt`
	temp=${temp#*:}
	temp="${temp%\"*}"
    temp="${temp#*\"}"
    width="${temp%,*}"
	
	temp=`grep height output/vr/interpolate/intermediate/probe.txt`
	temp=${temp#*:}
	temp="${temp%\"*}"
    temp="${temp#*\"}"
    height="${temp%,*}"
	
	PIXEL=$(( width * height ))
	
	if [ $PIXEL -gt $PIXELLIMIT ] ; then
		echo -e $"\e[91mError:\e[0m VRAM ($VRAM) insufficient for processing this video. $PIXEL > $PIXELLIMIT "
		mkdir -p input/vr/interpolate/error
		mv -fv -- "$INPUT" input/vr/interpolate/error
		exit 0
	fi
	
	uuid=$(openssl rand -hex 16)
	TARGETPREFIX=${INPUT##*/}
	INPUT=`realpath "$INPUT"`
	TARGETPREFIX_FPS=${TARGETPREFIX%.*}"_FPS_LR"
	TARGETPREFIX_CALL=vr/interpolate/intermediate/$TARGETPREFIX_FPS
	TARGETPREFIX=output/vr/interpolate/intermediate/$TARGETPREFIX_FPS
	FINALTARGETFOLDER=`realpath "output/vr/interpolate"`
	
	# RECOVERY : CHECK FOR OLD FILES AND EXTRACT UUID
	mkdir -p output/vr/interpolate/intermediate
	RECOVERY=
	OLDINTERMEDIATEFOLDERCOUNT=`find output/vr/interpolate/intermediate -type d -name "$TARGETPREFIX_FPS-"* | wc -l`
	if [ $OLDINTERMEDIATEFOLDERCOUNT -eq 1 ]; then
		SEGDIR=`find output/vr/interpolate/intermediate -type d -name "$TARGETPREFIX_FPS-"*`
		olduuid=${SEGDIR##*-}
		olduuid=${olduuid%.tmpseg}
		if [ -e output/vr/interpolate/intermediate/$TARGETPREFIX_FPS"-"$olduuid".tmpseg" ] && [ -e output/vr/interpolate/intermediate/$TARGETPREFIX_FPS".tmpfps/concat.sh" ] ; then
			uuid=$olduuid
			SEGDIR=`realpath "$SEGDIR"`
			FPSDIR="$TARGETPREFIX"".tmpfps"
			FPSDIR_CALL="$TARGETPREFIX_CALL"".tmpfps"
			TARGETPREFIX=`realpath "$TARGETPREFIX"`
			SPLITINPUT="$INPUT"
			EXTENSION="${INPUT##*.}"
			RECOVERY=X
		fi
	fi
	
	if [ -z "$RECOVERY" ]; then
		mkdir -p "$TARGETPREFIX""-$uuid"".tmpseg"
		mkdir -p "$TARGETPREFIX"".tmpfps"
		SEGDIR=`realpath "$TARGETPREFIX""-$uuid"".tmpseg"`
		FPSDIR="$TARGETPREFIX"".tmpfps"
		FPSDIR_CALL="$TARGETPREFIX_CALL"".tmpfps"
		if [ ! -e "$FPSDIR/concat.sh" ]
		then
			RECOVERY=
			touch "$TARGETPREFIX"".tmpfps"/x
			touch "$TARGETPREFIX""-$uuid"".tmpseg"/x
			rm "$TARGETPREFIX""-$uuid"".tmpseg"/* "$TARGETPREFIX"".tmpfps"/*
		fi
		touch $TARGETPREFIX
		TARGETPREFIX=`realpath "$TARGETPREFIX"`
		echo "Interpolating fps from $TARGETPREFIX"
		rm "$TARGETPREFIX"

		SPLITINPUT="$INPUT"
		EXTENSION="${INPUT##*.}"
		if [[ "$EXTENSION" == "webm" ]] || [[ "$EXTENSION" == "WEBM" ]] ; then
			echo "handling unsupported image format"
			NEWTARGET="${SPLITINPUT%.*}"".mp4"
			nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y  -i "$SPLITINPUT" "$NEWTARGET"
			SPLITINPUT=$NEWTARGET
			cp -- $SPLITINPUT $SEGDIR
			SPLITINPUT="$SEGDIR/"`basename $SPLITINPUT`		
		fi
	fi



	if [ ! -e "$FPSDIR/concat.sh" ]
	then
		WIDTH=`"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $SPLITINPUT`
		HEIGHT=`"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $SPLITINPUT`
		PIXEL=$(( $WIDTH * $HEIGHT ))

		RESLIMIT=3840
		
		duration=`"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=nw=1:nk=1 $SPLITINPUT`
		duration=${duration%.*}
		if test $duration -ge 60 ; then
			[ $loglevel -ge 1 ] && echo "long video detected."
			RESLIMIT=1920
		fi

		# Prepare to restrict resolution, and skip low res
		if test $WIDTH -lt 128 -o $HEIGHT -lt  128
		then
			echo "Skipping low resolution video: $SPLITINPUT"
		elif test $WIDTH -gt $RESLIMIT 
		then 
			echo "H-Resolution > $RESLIMIT: Downscaling..."
			$(dirname "$0")/v2v_limiter.sh "$SPLITINPUT"
			SPLITINPUT="${SPLITINPUT%.mp4}_4K"".mp4"
			mv -f -- $SPLITINPUT $SEGDIR
			SPLITINPUT="$SEGDIR/"`basename $SPLITINPUT`
		elif test $HEIGHT -gt $RESLIMIT
		then 
			echo "V-Resolution > $RESLIMIT: Downscaling..."
			$(dirname "$0")/v2v_limiter.sh "$SPLITINPUT"
			SPLITINPUT="${SPLITINPUT%.mp4}_4K"".mp4"
			mv -f -- $SPLITINPUT $SEGDIR
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
	if [ ! -e "$FPSDIR/concat.sh" ]
	then
		echo "Splitting into segments"
		nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i "$SPLITINPUT" -c:v libx264 -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" -crf 17 -map 0:v:0 $AUDIOMAPOPT -segment_time $SEGMENTTIME -g 9 -sc_threshold 0 -force_key_frames "expr:gte(t,n_forced*9)" -f segment -segment_start_number 1 -max_muxing_queue_size 9999 "$SEGDIR/segment%05d.mp4"
		# -max_muxing_queue_size 9999 
		if [ ! -e "$SEGDIR/segment00001.mp4" ]; then
			echo -e $"\e[91mError:\e[0m No segments!"
			exit 1
		fi
	fi
	echo "Prompting ..."
	for f in "$SEGDIR"/segment*.mp4 ; do
		f2=${f%.mp4}
		f2=${f2#$SEGDIR/segment}
		if [ ! -e "$FPSDIR/fpssegment_"$f2"_.mp4" ]
		then
			[ $loglevel -ge 0 ] && echo -ne "- $f2...       \r"
			if [[ ! $TESTAUDIO =~ "[STREAM]" ]]; then
				# create audio
				mv "$f" "${f%.mp4}_na.mp4"
				nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 -i "${f%.mp4}_na.mp4" -y -f ffmetadata metadata.txt -c:v copy -c:a aac -shortest "$f"
				rm -f -- "${f%.mp4}_na.mp4"
			fi
			status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
			if [ "$status" = "closed" ]; then
				echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
				exit 1
			fi
			# "$VIDEO_FORMAT" "$VIDEO_PIXFMT" "$VIDEO_CRF"
			echo -ne $"\e[91m" ; "$PYTHON_BIN_PATH"python.exe $SCRIPTPATH "$f" "$FPSDIR_CALL"/sbssegment "$multiplicator" ; echo -ne $"\e[0m"
		else
			[ $loglevel -ge 0 ] && echo -ne "+ $f2...       \r"
		fi
	done

	[ $loglevel -ge 0 ] && echo "Jobs running...   "
	
	if [ ! -e "$FPSDIR/concat.sh" ]
	then
		echo "#!/bin/sh" >"$FPSDIR/concat.sh"
		echo "cd \"\$(dirname \"\$0\")\"" >>"$FPSDIR/concat.sh"
		echo "FPSOPTION=\"$FPSOPTION\"" >>"$FPSDIR/concat.sh"
		echo "rm -rf \"$SEGDIR\"" >>"$FPSDIR/concat.sh"
		echo "if [ -e ./fpssegment_00001-audio.mp4 ]" >>"$FPSDIR/concat.sh"
		echo "then" >>"$FPSDIR/concat.sh"
		echo "    list=\`find . -type f -print | grep mp4 | grep -v audio\`" >>"$FPSDIR/concat.sh"
		echo "    rm \$list" >>"$FPSDIR/concat.sh"
		echo "fi" >>"$FPSDIR/concat.sh"
		echo "for f in ./*.mp4 ; do" >>"$FPSDIR/concat.sh"
		echo "	echo \"file \$f\" >> $CWD/"$FPSDIR"/list.txt" >>"$FPSDIR/concat.sh"
		echo "done" >>"$FPSDIR/concat.sh"
		echo "$FFMPEGPATHPREFIX""ffprobe -i $INPUT -show_streams -select_streams a -loglevel error >TESTAUDIO.txt 2>&1"  >>"$FPSDIR/concat.sh"
		echo "TESTAUDIO=\`cat TESTAUDIO.txt\`"  >>"$FPSDIR/concat.sh"
		echo "if [[ \"\$TESTAUDIO\" =~ \"[STREAM]\" ]]; then" >>"$FPSDIR/concat.sh"
		echo "    nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i list.txt -c copy -max_muxing_queue_size 9999 output.mp4" >>"$FPSDIR/concat.sh"
		echo "    nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i output.mp4 -i $INPUT -c copy -map 0:v:0 -map 1:a:0 -max_muxing_queue_size 9999 output2.mp4" >>"$FPSDIR/concat.sh"
		#echo "    nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i output2.mp4 -i fpssegment_00001.png -map 1 -map 0 -c copy -disposition:0 attached_pic -max_muxing_queue_size 9999 output3.mp4" >>"$FPSDIR/concat.sh"
		echo "    nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i output2.mp4 $SETMETADATA -vcodec libx264 -x264opts \"frame-packing=3\" -force_key_frames \"expr:gte(t,n_forced*1)\" -max_muxing_queue_size 9999 $TARGETPREFIX"".mp4" >>"$FPSDIR/concat.sh"
		echo "else" >>"$FPSDIR/concat.sh"
		echo "    nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i list.txt -c copy output2.mp4" >>"$FPSDIR/concat.sh"
		#echo "    nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i output2.mp4 -i fpssegment_00001.png -map 1 -map 0 -c copy -disposition:0 attached_pic -max_muxing_queue_size 9999 output3.mp4" >>"$FPSDIR/concat.sh"
		echo "    nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i output2.mp4 $SETMETADATA -vcodec libx264 -x264opts \"frame-packing=3\" -force_key_frames \"expr:gte(t,n_forced*1)\" -max_muxing_queue_size 9999 $TARGETPREFIX"".mp4" >>"$FPSDIR/concat.sh"
		echo "fi" >>"$FPSDIR/concat.sh"
		echo "if [ -e $TARGETPREFIX"".mp4 ]" >>"$FPSDIR/concat.sh"
		echo "then" >>"$FPSDIR/concat.sh"
		echo "    [ -e \"$EXIFTOOLBINARY\" ] && \"$EXIFTOOLBINARY\" -all:all= -overwrite_original $TARGETPREFIX"".mp4" >>"$FPSDIR/concat.sh"
		echo "    [ -e \"$EXIFTOOLBINARY\" ] && \"$EXIFTOOLBINARY\" -m -tagsfromfile \"$INPUT\" -ItemList:Title -ItemList:Comment -creditLine -overwrite_original $TARGETPREFIX"".mp4 && echo \"ItemList tags copied.\"" >>"$FPSDIR/concat.sh"
		echo "    [ -e \"$EXIFTOOLBINARY\" ] && \"$EXIFTOOLBINARY\" -m '-creditLine<\\\$creditLine''. VR we are - https://civitai.com/models/1757677 .' -overwrite_original $TARGETPREFIX"".mp4" >>"$FPSDIR/concat.sh"
		echo "    mkdir -p $FINALTARGETFOLDER" >>"$FPSDIR/concat.sh"
		echo "    mv -- $TARGETPREFIX"".mp4"" $FINALTARGETFOLDER" >>"$FPSDIR/concat.sh"
		echo "    cd .." >>"$FPSDIR/concat.sh"
		echo "    rm -rf \"$TARGETPREFIX\"\".tmpfps\"" >>"$FPSDIR/concat.sh"
		echo "    mkdir -p $CWD/input/vr/interpolate/done" >>"$FPSDIR/concat.sh"
		echo "    mv -fv -- $INPUT $CWD/input/vr/interpolate/done" >>"$FPSDIR/concat.sh"
		echo "    echo -e \$\"\\e[92mdone.\\e[0m\"" >>"$FPSDIR/concat.sh"
		echo "else" >>"$FPSDIR/concat.sh"
		echo "    echo -e \$\"\\e[91mError\\e[0m: Concat failed.\"" >>"$FPSDIR/concat.sh"
		echo "    mkdir -p input/vr/interpolate/error" >>"$FPSDIR/concat.sh"
		echo "    mv -fv -- $INPUT $CWD/input/vr/interpolate/error" >>"$FPSDIR/concat.sh"
		echo "    exit -1" >>"$FPSDIR/concat.sh"
		echo "fi" >>"$FPSDIR/concat.sh"
	fi
	
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
			exit 1
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
	echo "Calling $FPSDIR/concat.sh"
	$FPSDIR/concat.sh || exit 1
	
fi
exit 0

