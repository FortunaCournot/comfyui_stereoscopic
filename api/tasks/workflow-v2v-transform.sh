#!/bin/sh
#
# workflow-v2v-transform.sh
#
# transforms a base video (input) and places result under ComfyUI/output/vr/tasks folder.
#
# Copyright (c) 2026 Fortuna Cournot. MIT License. www.3d-gallery.org

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).
# Prerequisite: Configured path variables below.
# Prerequisite: Git Bash installed. Call this script in Git Bash

# - It will detect scene changes in the input video and generate a work plan,
# - It will generate input images accoording to work plan ,
# - it will generate transformed images accoording to workplan using the configured i2i workflow via api,
# - it will generate video segements based transformed images according to work plan using configured FL2V workflow.
# - concat video segements to final video, and apply audio from source video.

# either start this script in ComfyUI folder or enter absolute path of ComfyUI folder in your ComfyUI_windows_portable here
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi

assertlimit() {
    mode_upperlimit=$1
    kv=$2
	
    key=${kv%=*}
    value2=$(( ${kv#*=} ))

    temp=`grep "$key" output/vr/tasks/intermediate/probe.txt`
	temp=${temp#*:}
    temp="${temp%,*}"
	temp="${temp%\"*}"
    temp="${temp#*\"}"
	value1=$(( $temp ))

    if [ "$mode_upperlimit" != "true" ] ; then tmp="$value1" ; value1="$value2" ; value2="$tmp" ; fi
	
    if [ "$value1" -gt "$value2" ] ; then
		echo -e $"\e[32mLimit already fullfilled:\e[0m $key"": $value1 > $value2"". Skip processing and forwarding to output."
		mv -vf -- "$INPUT" "$FINALTARGETFOLDER"
		exit 0
	else
		echo "Condition met. $key"": $value1 <= $value2"
	fi
} 


COMFYUIPATH=`realpath $(dirname "$0")/../../../..`

if test $# -ne 3 
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 jsonblueprintpath taskname inputfile"
else
	
	cd $COMFYUIPATH

	CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

	# API relative to COMFYUIPATH, or absolute path:
	SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/python/workflow/v2v_simple.py

	NOLINE=-ne
	
	export CONFIGFILE
	if [ -e $CONFIGFILE ] ; then
		loglevel=$(awk -F "=" '/loglevel=/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
		[ $loglevel -ge 2 ] && set -x
		[ $loglevel -ge 2 ] && NOLINE="" ; echo $NOLINE
		config_version=$(awk -F "=" '/config_version=/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
#		COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST=/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
#		COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT=/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
#		export COMFYUIHOST COMFYUIPORT
	else
		echo -e $"\e[91mError:\e[0m No config!?"
		exit 1
	fi

	# set FFMPEGPATHPREFIX if ffmpeg binary is not in your enviroment path
	FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX=/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}

	EXIFTOOLBINARY=$(awk -F "=" '/EXIFTOOLBINARY=/ {print $2}' $CONFIGFILE) ; EXIFTOOLBINARY=${EXIFTOOLBINARY:-""}

	# workflow config variables
	SCENE_OFFSET_START=$(awk -F "=" '/SCENE_OFFSET_START=/ {print $2}' $CONFIGFILE)
	SCENE_OFFSET_START=${SCENE_OFFSET_START:-1}
	SCENE_OFFSET_END=$(awk -F "=" '/SCENE_OFFSET_END=/ {print $2}' $CONFIGFILE)
	SCENE_OFFSET_END=${SCENE_OFFSET_END:-1}
	SCENE_SEG_MAX_FRAMES=$(awk -F "=" '/SCENE_SEG_MAX_FRAMES=/ {print $2}' $CONFIGFILE)
	SCENE_SEG_MAX_FRAMES=${SCENE_SEG_MAX_FRAMES:-48}
	SCENE_WORKFLOW_FPS=$(awk -F "=" '/SCENE_WORKFLOW_FPS=/ {print $2}' $CONFIGFILE)
	SCENE_WORKFLOW_FPS=${SCENE_WORKFLOW_FPS:-16}

#	status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
#	if [ "$status" = "closed" ]; then
#		echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
#		exit 1
#	fi

	# Use Systempath for python by default, but set it explictly for comfyui portable.
	PYTHON_BIN_PATH=
	if [ -d "../python_embeded" ]; then
	  PYTHON_BIN_PATH=../python_embeded/
	fi

	BLUEPRINTCONFIG="$1"
	shift
	TASKNAME="$1"
	shift
	INPUT="$1"
	shift

	PROGRESS=" "
	if [ -e input/vr/tasks/BATCHPROGRESS.TXT ]
	then
		PROGRESS=`cat input/vr/tasks/BATCHPROGRESS.TXT`" "
	fi
	regex="[^/]*$"
	echo "========== $PROGRESS"`echo $INPUT | grep -oP "$regex"`" =========="
	
	mkdir -p output/vr/tasks/intermediate

	`"$FFMPEGPATHPREFIX"ffprobe -hide_banner -v error -select_streams V:0 -show_entries stream=bit_rate,width,height,r_frame_rate,duration,nb_frames -of json -i "$INPUT" >output/vr/tasks/intermediate/probe.txt`
	`"$FFMPEGPATHPREFIX"ffprobe -hide_banner -v error -select_streams a:0 -show_entries stream=codec_type -of json -i "$INPUT" >>output/vr/tasks/intermediate/probe.txt`

	upperlimits=`cat "$BLUEPRINTCONFIG" | grep -o '"upperlimits":[^"]*"[^"]*"' | sed -E 's/".*".*"(.*)"/\1/'`
	for parameterkv in $(echo $upperlimits | sed "s/,/ /g")
	do
		assertlimit "true" "$parameterkv"
	done
	
	lowerlimits=`cat "$BLUEPRINTCONFIG" | grep -o '"lowerlimits":[^"]*"[^"]*"' | sed -E 's/".*".*"(.*)"/\1/'`
	for parameterkv in $(echo $lowerlimits | sed "s/,/ /g")
	do
		assertlimit "false" "$parameterkv"
	done


	ORIGINALINPUT="$INPUT"
	TARGETPREFIX=${INPUT##*/}
	TARGETPREFIX=output/vr/tasks/intermediate/${TARGETPREFIX%.*}
	TARGETPREFIX=`realpath "$TARGETPREFIX"`
	FINALTARGETFOLDER=`realpath "output/vr/tasks/$TASKNAME"`
	mkdir -p $FINALTARGETFOLDER

	# Check for existing workplan for this source video (allows resuming)
	ORIGINALINPUT="$INPUT"
	ORIG_BASENAME=$(basename "$ORIGINALINPUT")
	REUSE_WORKPLAN=""
	rm -rf -- input/vr/tasks/intermediate/*
	for d in input/vr/tasks/intermediate/* ; do
		if [ -d "$d" ] && [ -e "$d/workplan.json" ] ; then
			# Only accept workplans that explicitly declare this video as "source"
			if grep -E -q "\"source\"[[:space:]]*:[[:space:]]*\"${ORIG_BASENAME}\"" "$d/workplan.json" ; then
				INTERMEDIATE_INPUT_FOLDER="$d"
				REUSE_WORKPLAN=1
				echo "Found existing workplan in $INTERMEDIATE_INPUT_FOLDER; reusing."
				break
			fi
		fi
	done
	if [ -z "$REUSE_WORKPLAN" ] ; then
		uuid=$(openssl rand -hex 16)
		INTERMEDIATE_INPUT_FOLDER=input/vr/tasks/intermediate/$uuid
		mkdir -p $INTERMEDIATE_INPUT_FOLDER
	fi
	EXTENSION="${INPUT##*.}"
	VIDEOINTERMEDIATE=$INTERMEDIATE_INPUT_FOLDER/tmp-input.$EXTENSION
	if [ -z "$REUSE_WORKPLAN" ] ; then
		# Re-encode input to a workflow-specific FPS intermediate file to avoid frame-rate issues
		echo "Converting input to $SCENE_WORKFLOW_FPS FPS -> $VIDEOINTERMEDIATE"
		"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -y -i "$INPUT" -filter:v "fps=$SCENE_WORKFLOW_FPS" -c:v libx264 -preset veryfast -crf 18 -c:a copy "$VIDEOINTERMEDIATE"
		if [ $? -ne 0 ]; then
			echo -e $"\e[91mError:\e[0m ffmpeg failed converting to $SCENE_WORKFLOW_FPS FPS"
			mkdir -p input/vr/tasks/$TASKNAME/error
			mv -- $ORIGINALINPUT input/vr/tasks/$TASKNAME/error
			rm -rf -- $INTERMEDIATE_INPUT_FOLDER
			exit 1
		fi
	fi

	# SECTION: detect scene changes in the input video and generate a work plan,

	if [ -n "$REUSE_WORKPLAN" ] ; then
		# Reuse existing workplan; set paths
		WORKPLAN_FILE="$INTERMEDIATE_INPUT_FOLDER/workplan.json"
		SCENES_FILE="$INTERMEDIATE_INPUT_FOLDER/scenes.txt"
		echo "Reusing existing workplan: $WORKPLAN_FILE"
	else
		# --- Scene detection: produce a list of scene cut times (one value per line)
		# Threshold can be overridden in the config file via SCENEDETECTION_THRESHOLD_DEFAULT
		SCENE_THRESHOLD=$(awk -F "=" '/SCENEDETECTION_THRESHOLD_DEFAULT=/ {print $2}' $CONFIGFILE)
		SCENE_THRESHOLD=${SCENE_THRESHOLD:-0.1}
		SCENES_FILE="$INTERMEDIATE_INPUT_FOLDER/scenes.txt"
		echo "Detecting scenes (threshold=$SCENE_THRESHOLD) -> $SCENES_FILE"
		"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -y -i "$VIDEOINTERMEDIATE" -filter:v "select='gt(scene,$SCENE_THRESHOLD)',showinfo" -f null - 2>&1 | grep showinfo | grep pts_time:[0-9.]\* -o | grep [0-9.]\* -o > "$SCENES_FILE"
		echo "Wrote s -> $SCENES_FILE"
		echo "---"
		cat $SCENES_FILE
		echo "---"
		if [ -z "$SCENES_FILE" ]; then
			echo -e $"\e[91mError:\e[0m Task failed. scene detection returned non-zero exit code"
			mkdir -p input/vr/tasks/$TASKNAME/error
			mv -- $ORIGINALINPUT input/vr/tasks/$TASKNAME/error
			rm -rf -- $INTERMEDIATE_INPUT_FOLDER
		fi

		# --- Create a basic workplan JSON next to the scenes file. Include source filename.
		WORKPLAN_FILE="$INTERMEDIATE_INPUT_FOLDER/workplan.json"
		if [ -e "$SCENES_FILE" ]; then
			# Build a JSON array from lines in scenes.txt
			scenes_json=$(awk 'BEGIN{printf "["} NR>1{printf ","} {printf "\"%s\"", $0} END{printf "]"}' "$SCENES_FILE")
		else
			scenes_json="[]"
		fi
		# --- Build `segments` based on `scenes` and optional offsets
		# last frame index (for final segment)., subtract 1 from count so last_frame is zero-based (index of last frame)
		set -x
		`"$FFMPEGPATHPREFIX"ffprobe -hide_banner -v error -select_streams V:0 -show_entries stream=nb_frames -of json -i "$VIDEOINTERMEDIATE" >$INTERMEDIATE_INPUT_FOLDER/probe.txt`
		set +x
		echo "---"
		cat $INTERMEDIATE_INPUT_FOLDER/probe.txt
		echo "---"
		last_frame=$(grep -oP '(?<="nb_frames": ")[^\"]*' $INTERMEDIATE_INPUT_FOLDER/probe.txt | head -n1)
		if [ -z "$FPSlast_frame" ]; then
			# fallback: try without lookbehind (older grep)
			last_frame=$(grep -o '"nb_frames"[[:space:]]*:[[:space:]]*"[^"]*"' $INTERMEDIATE_INPUT_FOLDER/probe.txt | sed -E 's/.*"([0-9\/\.]+)".*/\1/' | head -n1)
		fi
		last_frame=$((last_frame - 1))
		# iterate scenes and print each scene time (will be used later to build segments_json)
		# initialize segments_json accumulator
		segments_json="["
		segments_first=1
		if [ -e "$SCENES_FILE" ]; then
			idx=0
			prev_frame=0
			while IFS= read -r scene_time || [ -n "$scene_time" ]; do
				# compute frame index for the scene time (intermediate video uses $SCENE_WORKFLOW_FPS FPS)
				frame_index=$(awk -v t="$scene_time" -v fps="$SCENE_WORKFLOW_FPS" 'BEGIN{printf "%d", int(t*fps+0.5)}')
				# calculate number of target frames
				seg_target_frames=$((frame_index - prev_frame))
				idx_a=$((prev_frame + SCENE_OFFSET_START))
				idx_b=$((frame_index - 1 - SCENE_OFFSET_END))
				# output: index previous_frame_index current_frame_index
				seg_effectiveframes=$((idx_b - idx_a))
				if [ $seg_effectiveframes -lt 1 ] ; then
					continue
				fi
				seg_frames=$seg_target_frames
					while [ $seg_effectiveframes -gt $SCENE_SEG_MAX_FRAMES ] ; do
						idx_b=$((idx_a + SCENE_SEG_MAX_FRAMES - 1))
						echo "$idx $idx_a $idx_b $SCENE_SEG_MAX_FRAMES"
						# append fourth value to segments_json
						if [ $segments_first -eq 1 ] ; then
							segments_json="${segments_json}${SCENE_SEG_MAX_FRAMES}"
							segments_first=0
						else
							segments_json="${segments_json},${SCENE_SEG_MAX_FRAMES}"
						fi
						idx=$((idx+1))
						idx_a=$((idx_a + SCENE_SEG_MAX_FRAMES))
						seg_effectiveframes=$((seg_effectiveframes - SCENE_SEG_MAX_FRAMES))
						seg_frames=$((seg_frames - SCENE_SEG_MAX_FRAMES))
					done
					echo "$idx $idx_a $idx_b $seg_frames"
					# append fourth value (seg_frames) to segments_json
					if [ $segments_first -eq 1 ] ; then
						segments_json="${segments_json}${seg_frames}"
						segments_first=0
					else
						segments_json="${segments_json},${seg_frames}"
					fi
				prev_frame=$frame_index
				idx=$((idx+1))
			done < "$SCENES_FILE"
			seg_target_frames=$((last_frame - prev_frame + 1))
			echo "$idx $prev_frame $last_frame $seg_target_frames"  # final segment till end of video
			# append final segment length to segments_json
			if [ $segments_first -eq 1 ] ; then
				segments_json="${segments_json}${seg_target_frames}"
				segments_first=0
			else
				segments_json="${segments_json},${seg_target_frames}"
			fi
		else
			echo "(no scenes)"
		fi
		# close segments_json and write skeleton workplan (scenes filled, segments left empty) and include source
		segments_json="${segments_json}]"
		echo "{\"source\": \"${ORIG_BASENAME}\", \"scenes\": $scenes_json, \"segments\": $segments_json}" > "$WORKPLAN_FILE"
		echo "Wrote workplan -> $WORKPLAN_FILE"
		echo "---"
		cat "$WORKPLAN_FILE"
		echo "---"
	fi



	


	# SECTION: generate input images accoording to work plan ,

	# SECTION: generate transformed images accoording to workplan using the configured i2i workflow via api,

	# SECTION: generate video segements based transformed images according to work plan using configured FL2V workflow.

	# SECTION: concat video segements to final video, and apply audio from source video.



fi
exit 0

