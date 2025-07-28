#!/bin/sh
#
# v2v_upscale_downscale.sh
#
# Upscales a base video (input) by 4x_foolhardy_Remacri , then downscales it and places result under ComfyUI/output/vr/scaling folder.
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
# API relative to COMFYUIPATH, or absolute path:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/python/v2v_upscale_downscale.py


if test $# -ne 2 -a $# -ne 3
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 input [upscalefactor]"
    echo "E.g.: $0 SmallIconicTown.mp4 overwide_active [upscalefactor]"
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

	# set FFMPEGPATHPREFIX if ffmpeg binary is not in your enviroment path
	FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}

	# Use Systempath for python by default, but set it explictly for comfyui portable.
	PYTHON_BIN_PATH=
	if [ -d "../python_embeded" ]; then
	  PYTHON_BIN_PATH=../python_embeded/
	fi

	DOWNSCALE=1.0
	INPUT="$1"
	shift
	overwide_active=$1
	shift
	
	UPSCALEFACTOR=0
	if test $# -eq 1
	then
		UPSCALEFACTOR="$1"
		if [ "$UPSCALEFACTOR" -eq 4 ]
		then
			TARGETPREFIX="$TARGETPREFIX""_x4"
			DOWNSCALE=1.0
		elif [ "$UPSCALEFACTOR" -eq 2 ]
		then
			TARGETPREFIX="$TARGETPREFIX""_x2"
			DOWNSCALE=0.5
		else
			 echo -e $"\e[91mError:\e[0m Allowed upscalefactor values: 2 or 4"
			exit
		fi
	fi
	
	PROGRESS=" "
	if [ -e input/vr/scaling/BATCHPROGRESS.TXT ]
	then
		PROGRESS=`cat input/vr/scaling/BATCHPROGRESS.TXT`" "
	fi
	regex="[^/]*$"
	echo "========== $PROGRESS""rescale "`echo $INPUT | grep -oP "$regex"`" =========="
	
	TARGETPREFIX=${INPUT##*/}
	INPUT=`realpath "$INPUT"`
	TARGETPREFIX=output/vr/scaling/intermediate/${TARGETPREFIX%.mp4}
	FINALTARGETFOLDER=`realpath "output/vr/scaling"`
	
	UPSCALEMODEL="RealESRGAN_x4plus.pth"
	SCALEBLENDFACTOR=$(awk -F "=" '/SCALEBLENDFACTOR/ {print $2}' $CONFIGFILE) ; SCALEBLENDFACTOR=${SCALEBLENDFACTOR:-"0.7"}
	SCALESIGMARESOLUTION=$(awk -F "=" '/SCALESIGMARESOLUTION/ {print $2}' $CONFIGFILE) ; SCALESIGMARESOLUTION=${SCALESIGMARESOLUTION:-"1920.0"}
	
	RESW=`"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 $INPUT`
	RESH=`"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 $INPUT`
	PIXEL=$(( $RESW * $RESH ))
	
	LIMIT4X=500000
	LIMIT2X=2000000
	if [ $overwide_active -eq 1 ]; then
		LIMIT2X=4000000
	fi
	
	if [ "$UPSCALEFACTOR" -eq 0 ]
	then
		if [ $PIXEL -lt $LIMIT2X ]; then
			if [ $PIXEL -lt $LIMIT4X ]; then
				TARGETPREFIX="$TARGETPREFIX""_x4"
				UPSCALEMODEL=$(awk -F "=" '/UPSCALEMODELx4/ {print $2}' $CONFIGFILE) ; UPSCALEMODEL=${UPSCALEMODEL:-"RealESRGAN_x4plus.pth"}
				DOWNSCALE=$(awk -F "=" '/RESCALEx4/ {print $2}' $CONFIGFILE) ; DOWNSCALE=${DOWNSCALE:-"1.0"}
				UPSCALEFACTOR=4
			else
				TARGETPREFIX="$TARGETPREFIX""_x2"
				UPSCALEMODEL=$(awk -F "=" '/UPSCALEMODELx2/ {print $2}' $CONFIGFILE) ; UPSCALEMODEL=${UPSCALEMODEL:-"RealESRGAN_x4plus.pth"}
				DOWNSCALE=$(awk -F "=" '/RESCALEx2/ {print $2}' $CONFIGFILE) ; DOWNSCALE=${DOWNSCALE:-"0.5"}
				UPSCALEFACTOR=2
			fi
		fi
	fi
	
	if [ "$UPSCALEFACTOR" -gt 0 ]
	then
		uuid=$(openssl rand -hex 16)
		mkdir -p "$TARGETPREFIX"".tmpupscale"
		SEGDIR=`realpath "$TARGETPREFIX""-$uuid"".tmpseg"`
		UPSCALEDIR=`realpath "$TARGETPREFIX"".tmpupscale"`
		mkdir -p "$SEGDIR"
		mkdir -p "$UPSCALEDIR"
		if [ ! -e "$UPSCALEDIR/concat.sh" ]
		then
			touch "$TARGETPREFIX""-$uuid"".tmpseg"/x
			touch "$TARGETPREFIX"".tmpupscale"/x
			rm "$TARGETPREFIX""-$uuid"".tmpseg"/* "$TARGETPREFIX"".tmpupscale"/*
		fi
		touch $TARGETPREFIX
		TARGETPREFIX=`realpath "$TARGETPREFIX"`
		echo "prepare splitting $TARGETPREFIX"
		rm "$TARGETPREFIX"
	
		SPLITINPUT="$INPUT"
		if [ ! -e "$UPSCALEDIR/concat.sh" ]
		then
			# Prepare to restrict tp 30 fps (script batch maximum)
			fpsv=`"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=nw=1:nk=1 $SPLITINPUT`
			fps=$(($fpsv))
			echo "Source FPS: $fps ($fpsv)"
			FPSOPTION=`echo $fps 30.0 | awk '{if ($1 > $2) print "-filter:v fps=fps=30" }'`
			if [[ -n "$FPSOPTION" ]]
			then 
				SPLITINPUTFPS30="$SEGDIR/splitinput_fps30.mp4"
				echo "Rencoding to 30.0 ..."
				nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i "$SPLITINPUT" -filter:v fps=fps=30 "$SPLITINPUTFPS30"
				SPLITINPUT="$SPLITINPUTFPS30"
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
		if [ ! -e "$UPSCALEDIR/concat.sh" ]
		then
			echo "Splitting into segments"
			nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -i "$SPLITINPUT" -c:v libx264 -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" -crf 22 -map 0:v:0 $AUDIOMAPOPT -segment_time 1 -g 9 -sc_threshold 0 -force_key_frames "expr:gte(t,n_forced*9)" -f segment -segment_start_number 1 "$SEGDIR/segment%05d.mp4"
		fi
		echo "Prompting [$UPSCALEFACTOR"x"]..."
		for f in "$SEGDIR"/segment*.mp4 ; do
			f2=${f%.mp4}
			f2=${f2#$SEGDIR/segment}
			echo -ne "$f2...       \r"
			if [ ! -e "$UPSCALEDIR/sbssegment_$f2.mp4" ]
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
				"$PYTHON_BIN_PATH"python.exe $SCRIPTPATH "$f" "$UPSCALEDIR"/sbssegment "$UPSCALEMODEL" "$DOWNSCALE" "$SCALEBLENDFACTOR" "$SCALESIGMARESOLUTION"
			fi
		done
		echo "Jobs running...   "
		
		
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
		echo "    echo audio remapped." >>"$UPSCALEDIR/concat.sh"
		echo "    nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i output2.mp4 -i thumbnail.png -map 1 -map 0 -c copy -disposition:0 attached_pic $TARGETPREFIX"".mp4" >>"$UPSCALEDIR/concat.sh"
		echo "else" >>"$UPSCALEDIR/concat.sh"
		echo "    echo no audio to remap." >>"$UPSCALEDIR/concat.sh"
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
		mkdir -p input/vr/scaling/done
		mv -fv "$INPUT" input/vr/scaling/done
		echo "Calling $UPSCALEDIR/concat.sh"
		$UPSCALEDIR/concat.sh
	else
		echo "Skipping upscaling of video $INPUT"
		mkdir -p "$FINALTARGETFOLDER"
		cp $INPUT "$FINALTARGETFOLDER"
		mkdir -p input/vr/scaling/done
		mv -fv "$INPUT" input/vr/scaling/done
	fi
fi

