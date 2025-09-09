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
		loglevel=$(awk -F "=" '/loglevel=/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
		[ $loglevel -ge 2 ] && set -x
		config_version=$(awk -F "=" '/config_version=/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
		COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST=/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
		COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT=/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
		export COMFYUIHOST COMFYUIPORT
	else
		touch "$CONFIGFILE"
		echo "config_version=1">>"$CONFIGFILE"
	fi

	EXIFTOOLBINARY=$(awk -F "=" '/EXIFTOOLBINARY=/ {print $2}' $CONFIGFILE) ; EXIFTOOLBINARY=${EXIFTOOLBINARY:-""}
	
	# set FFMPEGPATHPREFIX if ffmpeg binary is not in your enviroment path
	FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX=/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}

	multiplicator="$1"
	shift
	VRAM="$1"
	shift
	INPUT="$1"
	if [ ! -e "$1" ] ; then echo "input file removed: $INPUT"; exit 0; fi
	shift

	# Notice: At SEGMENTTIME=5 (63 frames 4K) crashes ComfyUI without error
	SEGMENTTIME=1
	
	VIDEO_FORMAT=$(awk -F "=" '/VIDEO_FORMAT=/ {print $2}' $CONFIGFILE) ; VIDEO_FORMAT=${VIDEO_FORMAT:-"video/h264-mp4"}
	VIDEO_PIXFMT=$(awk -F "=" '/VIDEO_PIXFMT=/ {print $2}' $CONFIGFILE) ; VIDEO_PIXFMT=${VIDEO_PIXFMT:-"yuv420p"}
	VIDEO_CRF=$(awk -F "=" '/VIDEO_CRF=/ {print $2}' $CONFIGFILE) ; VIDEO_CRF=${VIDEO_CRF:-"17"}

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
	if [[ $INPUT == *"_SBS_LR"* ]] ; then
		PIXELLIMIT=$(( 2 * PIXELLIMIT ))
	fi
	
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
		echo -e $"\e[91mError:\e[0m VRAM ($VRAM""GB) insufficient for processing this video resolution. $width"" x""$height = $PIXEL > $PIXELLIMIT "
		mkdir -p input/vr/interpolate/error
		mv -fv -- "$INPUT" input/vr/interpolate/error
		exit 0
	fi
	
	uuid=$(openssl rand -hex 16)
	TARGETPREFIX=${INPUT##*/}
	INPUT=`realpath "$INPUT"`
	TARGETPREFIX_FPS=${TARGETPREFIX%.*}
	TARGETPREFIX_CALL=vr/interpolate/intermediate/$TARGETPREFIX_FPS
	TARGETPREFIX=output/vr/interpolate/intermediate/$TARGETPREFIX_FPS
	FINALTARGETFOLDER=`realpath "output/vr/interpolate"`
	
	rm -rf -- "$TARGETPREFIX"".tmpfps" "$TARGETPREFIX""-"*".tmpseg" 2>/dev/null
	
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

	until [ "$queuecount" = "0" ]
	do
		sleep 1
		curl -silent "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json
		queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
		echo -ne "Waiting for old queue to finish. queuecount: $queuecount         \r"
	done

	start=`date +%s`
	startjob=$start
	
	JOBLIST="$SPLITINPUT"
	if [[ $INPUT == *"_SBS_LR"* ]] ; then
		echo "Splitting..."
		JOBLIST=
		set -x
		nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -v quiet -stats -y -i "$SPLITINPUT" -filter_complex "[0]crop=iw/2:ih:0:0[left];[0]crop=iw/2:ih:ow:0[right]" -map "[left]" "$TARGETPREFIX""-left-input.mp4" -map "[right]" "$TARGETPREFIX""-right-input.mp4"
		set +x
		
		if [ ! -e "$TARGETPREFIX""-right-input.mp4" ] || [ ! -e "$TARGETPREFIX""-left-input.mp4" ] ; then
				echo -e $"\e[91mError:\e[0m split failed. Check for error messages."
				mkdir -p input/vr/interpolate/error
				mv -vf -- "$INPUT" input/vr/interpolate/error
				exit 0
		fi
		
		JOBLIST=`find output/vr/interpolate/intermediate -maxdepth 1 -type f -name "$TARGETPREFIX_FPS""*-input.mp4"`
	fi
	
	declare -i INDEX=0
	for inputfile in $JOBLIST ; do
		INDEX+=1
		TESTAUDIO=""
		AUDIOMAPOPT=""

		echo "--- $INDEX $inputfile"
	
		echo "Splitting into segments"
		set -x
		nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i "$inputfile" -c:v libx264 -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" -crf 17 -map 0:v:0 $AUDIOMAPOPT -segment_time $SEGMENTTIME -g 9 -sc_threshold 0 -force_key_frames "expr:gte(t,n_forced*9)" -f segment -segment_start_number 1 -max_muxing_queue_size 9999 "$SEGDIR/segment%05d.mp4"
		set +x
		# -max_muxing_queue_size 9999 
		if [ ! -e "$SEGDIR/segment00001.mp4" ]; then
			echo -e $"\e[91mError:\e[0m No segments!"
			exit 1
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
					set -x
					nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 -i "${f%.mp4}_na.mp4" -y -f ffmetadata metadata.txt -c:v copy -c:a aac -shortest "$f"
					set +x
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
			echo "rm -f -- \"$SEGDIR/*\"" >>"$FPSDIR/concat.sh"
			echo "if [ -e ./fpssegment_00001-audio.mp4 ]" >>"$FPSDIR/concat.sh"
			echo "then" >>"$FPSDIR/concat.sh"
			echo "    list=\`find . -type f -print | grep mp4 | grep -v audio\`" >>"$FPSDIR/concat.sh"
			echo "    rm -- \$list" >>"$FPSDIR/concat.sh"
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
			echo "    mv -v -- $TARGETPREFIX"".mp4"" ../""$TARGETPREFIX""-part"$INDEX".mp4" >>"$FPSDIR/concat.sh"
			echo "    cd .." >>"$FPSDIR/concat.sh"
			echo "    rm -f -- \"$TARGETPREFIX\"\".tmpfps/*\"" >>"$FPSDIR/concat.sh"
			echo "    echo -e \$\"\\e[1mdone part "$INDEX".\\e[0m\"" >>"$FPSDIR/concat.sh"
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
		itertimemsg=""
		queuecount=
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
	
		rm queuecheck.json
		echo "Calling $FPSDIR/concat.sh"
		$FPSDIR/concat.sh || exit 1
	
		if [ -e $TARGETPREFIX"".mp4 ] ; then
			mv -f -- $TARGETPREFIX"".mp4 $TARGETPREFIX"-part"$INDEX.mp4
			rm "$TARGETPREFIX""-$uuid"".tmpseg"/* "$TARGETPREFIX"".tmpfps"/*
		else
			echo -e $"\e[91mError:\e[0m Failed to create part."
			mkdir -p input/vr/interpolate/error
			mv -vf -- "$INPUT" input/vr/interpolate/error
			exit 0
		fi
		
	done
	
	if [[ $INPUT == *"_SBS_LR"* ]] ; then
		rm -f -- "$TARGETPREFIX""-right-input.mp4" "$TARGETPREFIX""-left-input.mp4"

		echo "Joining..."

		TESTAUDIO=`"$FFMPEGPATHPREFIX"ffprobe -i "$INPUT" -show_streams -select_streams a -loglevel error | head -n 1`
		if [[ $TESTAUDIO =~ "[STREAM]" ]]; then
			set -x
			nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -v quiet -stats -y -i "$TARGETPREFIX""-part1.mp4" -i "$TARGETPREFIX""-part2.mp4" -i "$INPUT" -filter_complex "[0:v][1:v]hstack=inputs=2[v]" -map "[v]" -map "2:a" "$TARGETPREFIX".mp4
			set +x
		else
			set -x
			nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -v quiet -stats -y -i "$TARGETPREFIX""-part1.mp4" -i "$TARGETPREFIX""-part2.mp4" -i "$INPUT" -filter_complex "[0:v][1:v]hstack=inputs=2[v]" -map "[v]" "$TARGETPREFIX".mp4
			set +x
		fi
		if [ ! -e "$TARGETPREFIX".mp4 ] ; then
			echo -e $"\e[91mError:\e[0m join failed. Check for error messages."
			mkdir -p input/vr/interpolate/error
			mv -vf -- "$INPUT" input/vr/interpolate/error
			exit 0
		fi
		
		rm -f -- "$TARGETPREFIX""-part1.mp4""$TARGETPREFIX""-part2.mp4"

	else
		mv -f -- "$TARGETPREFIX""-part1.mp4" "$TARGETPREFIX".mp4
	fi

	mv -f -- "$TARGETPREFIX".mp4 "$FINALTARGETFOLDER"
	mkdir -p input/vr/interpolate/done
	# do not overwrite done because it can be self-looped
	if [ ! -e input/vr/interpolate/done/${INPUT%##*/} ] ; then mv -- "$INPUT" input/vr/interpolate/done ; fi
	
	runtime=$((end-startjob))
	echo -e $"\e[92mdone\e[0m duration: $runtime""s.                         "

fi
exit 0

