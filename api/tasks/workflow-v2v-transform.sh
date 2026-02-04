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

# Helper: run FL2V transition workflow to produce a chunk file
iv2v_generate() {
	img1="$1"
	img2="$2"
	chunk_file="$3"
	frames_to_generate="$4"
	start="$5"
	prompt="$6"
	# frames_to_generate is a count; compute inclusive end index (0-based)
	end=$((start + frames_to_generate - 1))

	control_chunk="$INTERMEDIATE_INPUT_FOLDER/control_${chunk_index}.mp4"

	# extract range of frames from VIDEOINTERMEDIATE into control_chunk
	echo "Extracting control chunk $control_chunk from $VIDEOINTERMEDIATE frames $start-$end"
	"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -y -i "$VIDEOINTERMEDIATE" -vf "select='between(n\,$start\,$end)'" -vsync 0 -c:v libx264 -preset veryfast -crf 18 -an "$control_chunk"
	if [ $? -ne 0 ] || [ ! -s "$control_chunk" ]; then
		echo -e $"\e[91mError:\e[0m Failed creating control chunk $control_chunk"
		mkdir -p input/vr/tasks/$TASKNAME/error
		mv -- $ORIGINALINPUT input/vr/tasks/$TASKNAME/error
		exit 1
	fi

	iv2v_api=`cat "$BLUEPRINTCONFIG" | grep -o '"iv2v_api":[^"]*"[^"]*"' | sed -E 's/".*".*"(.*)"/\1/'`

	img1=`realpath "$img1"`
	control_chunk=`realpath "$control_chunk"`

	[ $loglevel -lt 2 ] && set -x
	"$PYTHON_BIN_PATH"python.exe "$SCRIPTPATH2" "$iv2v_api" "$img1" "$control_chunk" "$INTERMEDIATE_OUTPUT_FOLDER/converted" "$frames_to_generate" "$prompt"
	set +x && [ $loglevel -ge 2 ] && set -x

	start=`date +%s`
	end=`date +%s`
	secs=0
	queuecount=""
	until [ "$queuecount" = "0" ]
	do
		sleep 1
		status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
		if [ "$status" = "closed" ] ; then
			echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
			return 1
		fi
		curl -silent "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json
		queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`

		end=`date +%s`
		secs=$((end-start))
		itertimemsg=`printf '%02d:%02d:%02s\n' $((secs/3600)) $((secs%3600/60)) $((secs%60))`
		echo -ne "$itertimemsg         \r"
	done
	runtime=$((end-start))
	[ $loglevel -ge 0 ] && echo "done. duration: $runtime""s.                             "

	EXTENSION=".mp4"
	INTERMEDIATE="$INTERMEDIATE_OUTPUT_FOLDER/converted""_00001_""${EXTENSION}"

	if [ -e "$INTERMEDIATE" ] && [ -s "$INTERMEDIATE" ] ; then
		mv -vf -- "$INTERMEDIATE" "$chunk_file"
		echo -e $"\e[92mstep done.\e[0m"
		return 0
	else
		echo -e $"\e[91mError:\e[0m Step failed. $INTERMEDIATE missing or zero-length."
		return 2
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
	SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/python/workflow/i2i_transition.py
	SCRIPTPATH2=./custom_nodes/comfyui_stereoscopic/api/python/workflow/iv2v_transition.py

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
	FINALTARGETFOLDER=`realpath "output/vr/tasks/$TASKNAME"`
	mkdir -p $FINALTARGETFOLDER

	# Check for existing workplan for this source video (allows resuming)
	ORIGINALINPUT="$INPUT"
	ORIG_BASENAME=$(basename "$ORIGINALINPUT")
	REUSE_WORKPLAN=""
	
	#rm -rf -- input/vr/tasks/intermediate/*
	rm -rf -- output/vr/tasks/intermediate/*
	
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
	# create corresponding output-side intermediate folder (output/..)
	INTERMEDIATE_OUTPUT_FOLDER=$(echo "$INTERMEDIATE_INPUT_FOLDER" | sed 's#^input/#output/#')
	mkdir -p "$INTERMEDIATE_OUTPUT_FOLDER"
	INTERMEDIATE_OUTPUT_FOLDER=`realpath "$INTERMEDIATE_OUTPUT_FOLDER"`



	TARGETPREFIX=${INPUT##*/}
	TARGETPREFIX=$INTERMEDIATE_OUTPUT_FOLDER/${TARGETPREFIX%.*}
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
		# initialize segments arrays: frame counts, start indices, end indices
		segments_framecount_json="["
		segments_start_json="["
		segments_end_json="["
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
				idx_seg_end=$idx_b
				# output: index previous_frame_index current_frame_index
				seg_effectiveframes=$((idx_b - idx_a))
				if [ $seg_effectiveframes -lt 1 ] ; then
					continue
				fi
				seg_frames=$seg_target_frames
				# split for SCENE_SEG_MAX_FRAMES
				while [ $seg_effectiveframes -gt $SCENE_SEG_MAX_FRAMES ] ; do
					idx_b=$((idx_a + SCENE_SEG_MAX_FRAMES - 1))
					# append values to arrays: framecount, start, end
					if [ $segments_first -eq 1 ] ; then
						segments_framecount_json="${segments_framecount_json}${SCENE_SEG_MAX_FRAMES}"
						segments_start_json="${segments_start_json}${idx_a}"
						segments_end_json="${segments_end_json}${idx_b}"
						segments_first=0
					else
						segments_framecount_json="${segments_framecount_json},${SCENE_SEG_MAX_FRAMES}"
						segments_start_json="${segments_start_json},${idx_a}"
						segments_end_json="${segments_end_json},${idx_b}"
					fi
					idx=$((idx+1))
					idx_a=$((idx_a + SCENE_SEG_MAX_FRAMES))
					seg_effectiveframes=$((seg_effectiveframes - SCENE_SEG_MAX_FRAMES))
					seg_frames=$((seg_frames - SCENE_SEG_MAX_FRAMES))
				done
				# append remaining chunk values to arrays
				if [ $segments_first -eq 1 ] ; then
					segments_framecount_json="${segments_framecount_json}${seg_frames}"
					segments_start_json="${segments_start_json}${idx_a}"
					segments_end_json="${segments_end_json}${idx_seg_end}"
					segments_first=0
				else
					segments_framecount_json="${segments_framecount_json},${seg_frames}"
					segments_start_json="${segments_start_json},${idx_a}"
					segments_end_json="${segments_end_json},${idx_seg_end}"
				fi
				prev_frame=$frame_index
				idx=$((idx+1))
			done < "$SCENES_FILE"
			# compute final segment start/end with offsets
			final_start=$((prev_frame + SCENE_OFFSET_START))
			final_end=$((last_frame - SCENE_OFFSET_END))
			seg_effectiveframes=$((final_end - final_start + 1))
			idx_a=$final_start
			# split final segment into chunks of at most SCENE_SEG_MAX_FRAMES
			while [ $seg_effectiveframes -gt $SCENE_SEG_MAX_FRAMES ] ; do
				idx_b=$((idx_a + SCENE_SEG_MAX_FRAMES - 1))
				if [ $segments_first -eq 1 ] ; then
					segments_framecount_json="${segments_framecount_json}${SCENE_SEG_MAX_FRAMES}"
					segments_start_json="${segments_start_json}${idx_a}"
					segments_end_json="${segments_end_json}${idx_b}"
					segments_first=0
				else
					segments_framecount_json="${segments_framecount_json},${SCENE_SEG_MAX_FRAMES}"
					segments_start_json="${segments_start_json},${idx_a}"
					segments_end_json="${segments_end_json},${idx_b}"
				fi
				idx_a=$((idx_a + SCENE_SEG_MAX_FRAMES))
				seg_effectiveframes=$((seg_effectiveframes - SCENE_SEG_MAX_FRAMES))
			done
			# append remaining frames (if any)
			if [ $seg_effectiveframes -gt 0 ] ; then
				idx_b=$((idx_a + seg_effectiveframes - 1))
				if [ $segments_first -eq 1 ] ; then
					segments_framecount_json="${segments_framecount_json}${seg_effectiveframes}"
					segments_start_json="${segments_start_json}${idx_a}"
					segments_end_json="${segments_end_json}${idx_b}"
					segments_first=0
				else
					segments_framecount_json="${segments_framecount_json},${seg_effectiveframes}"
					segments_start_json="${segments_start_json},${idx_a}"
					segments_end_json="${segments_end_json},${idx_b}"
				fi
			fi
		else
			echo "(no scenes)"
		fi
		# close segments arrays and write skeleton workplan (scenes filled, segments left empty) and include source
		segments_framecount_json="${segments_framecount_json}]"
		segments_start_json="${segments_start_json}]"
		segments_end_json="${segments_end_json}]"
		echo "{\"source\": \"${ORIG_BASENAME}\", \"scenes\": $scenes_json, \"segments_framecount\": $segments_framecount_json, \"segments_start\": $segments_start_json, \"segments_end\": $segments_end_json}" > "$WORKPLAN_FILE"
		echo "Wrote workplan -> $WORKPLAN_FILE"
		echo "---"
		cat "$WORKPLAN_FILE"
		echo "---"
	fi

	# SECTION: generate input images accoording to work plan ,

	# Prepare loop: read `segments_start` and `segments_end` from workplan and iterate
	# Workplan is at $WORKPLAN_FILE (created above in intermediate folder)
	if [ -e "$WORKPLAN_FILE" ]; then
		# extract numeric lists inside the brackets
		segments_start_vals=$(grep -o '"segments_start"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$WORKPLAN_FILE" | sed -E 's/.*\[([^]]*)\].*/\1/')
		segments_end_vals=$(grep -o '"segments_end"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$WORKPLAN_FILE" | sed -E 's/.*\[([^]]*)\].*/\1/')
		# if either is empty, treat as none
		if [ -z "$segments_start_vals" ] || [ -z "$segments_end_vals" ]; then
			echo "No segments found in $WORKPLAN_FILE"
		else
			# count entries by number of commas (+1)
			seg_count=1
			if echo "$segments_start_vals" | grep -q ','; then
				seg_count=$(echo "$segments_start_vals" | awk -F, '{print NF}')
			fi
			# iterate by index (1-based fields for cut)
			for idx in $(seq 1 $seg_count); do
				start=$(echo "$segments_start_vals" | cut -d',' -f$idx | tr -d '[:space:]')
				end=$(echo "$segments_end_vals" | cut -d',' -f$idx | tr -d '[:space:]')
				seg_index=$((idx-1))
				# skip if both images already exist (quiet check at loop start)
				tgt_start_img="$INTERMEDIATE_INPUT_FOLDER/start_${seg_index}.png"
				tgt_end_img="$INTERMEDIATE_INPUT_FOLDER/end_${seg_index}.png"
				if [ -f "$tgt_start_img" ] && [ -f "$tgt_end_img" ]; then
					# already extracted
					continue
				fi
				echo "Preparing segment $seg_index: start=$start end=$end"
				# create segment helper dir and metadata
				sb_dir="$INTERMEDIATE_INPUT_FOLDER/segment-$seg_index"
				mkdir -p "$sb_dir"
				# convert workplan (1-based) to ffmpeg 0-based indices
				start0=$((start - 1))
				end0=$((end - 1))
				echo "$start0" > "$sb_dir/start.txt"
				echo "$end0" > "$sb_dir/end.txt"
				# extract start frame if missing (ffmpeg expects 0-based index)
				if [ ! -f "$tgt_start_img" ]; then
					"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -loglevel error -y -i "$VIDEOINTERMEDIATE" -vf "select=eq(n\,$start0)" -vframes 1 -q:v 2 "$tgt_start_img"
					if [ $? -ne 0 ]; then
						echo "Warning: failed extracting start frame $start0 for segment $seg_index"
					fi
				fi
				# extract end frame if missing (ffmpeg expects 0-based index)
				if [ ! -f "$tgt_end_img" ]; then
					"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -loglevel error -y -i "$VIDEOINTERMEDIATE" -vf "select=eq(n\,$end0)" -vframes 1 -q:v 2 "$tgt_end_img"
					if [ $? -ne 0 ]; then
						echo "Warning: failed extracting end frame $end0 for segment $seg_index"
					fi
				fi
			done
		fi
	else
		echo -e $"\e[91mError:\e[0m Workplan not found: $WORKPLAN_FILE"
		mkdir -p input/vr/tasks/$TASKNAME/error
		mv -- $ORIGINALINPUT input/vr/tasks/$TASKNAME/error
		rm -rf -- $INTERMEDIATE_INPUT_FOLDER/*
		exit 1
	fi

	# SECTION: generate transformed images accoording to workplan using the configured i2i workflow via api,
	# Iterate segments and run ComfyUI workflow for start/end images (placeholder)
	for d in "$INTERMEDIATE_INPUT_FOLDER"/segment-*; do
		if [ ! -d "$d" ]; then
			# no segments found (glob didn't match)
			break
		fi
		seg_index=${d##*-}
		# check if i2i outputs already exist (first/last filenames); skip if present
		first_img="$INTERMEDIATE_INPUT_FOLDER/first_${seg_index}.png"
		last_img="$INTERMEDIATE_INPUT_FOLDER/last_${seg_index}.png"
		if [ -f "$first_img" ] ; then   # deactivated: && [ -f "$last_img" ]
			# i2i outputs already present for this segment, skip
			continue
		fi
		# iterate the two representative images for the segment (input images)
		for img in "$INTERMEDIATE_INPUT_FOLDER/start_${seg_index}.png" ; do   # deactivated "$INTERMEDIATE_INPUT_FOLDER/end_${seg_index}.png"
			if echo "$(basename "$img")" | grep -q '^start_' ; then
				target_img="$first_img"
			else
				target_img="$last_img"
			fi

			if [ -f "$target_img" ]; then
				echo "Resuming. image already exists: $target_img"
				continue
			fi

			if [ ! -f "$img" ]; then
				echo -e $"\e[91mError:\e[0m Task failed. input image $img missing."
				mkdir -p input/vr/tasks/$TASKNAME/error
				mv -- $ORIGINALINPUT input/vr/tasks/$TASKNAME/error
				exit 1
			fi

			# call the ComfyUI i2i workflow on $img and write outputs into INTERMEDIATE_OUTPUT_FOLDER
			echo "--- running i2i workflow for segment $seg_index -> $img"

			i2i_api=`cat "$BLUEPRINTCONFIG" | grep -o '"i2i_api":[^"]*"[^"]*"' | sed -E 's/".*".*"(.*)"/\1/'`
			
			INPUT=`realpath "$img"`
			[ $loglevel -lt 2 ] && set -x
			"$PYTHON_BIN_PATH"python.exe $SCRIPTPATH "$i2i_api" "$INPUT" "$INTERMEDIATE_OUTPUT_FOLDER/converted"
			set +x && [ $loglevel -ge 2 ] && set -x

			start=`date +%s`
			end=`date +%s`
			secs=0
			queuecount=""
			until [ "$queuecount" = "0" ]
			do
				sleep 1
				
				status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
				if test $# -ne 0
				then	
					echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
					exit 1
				fi
				curl -silent "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json
				queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
			
				end=`date +%s`
				secs=$((end-start))
				itertimemsg=`printf '%02d:%02d:%02s\n' $((secs/3600)) $((secs%3600/60)) $((secs%60))`
				echo -ne "$itertimemsg         \r"
			done
			runtime=$((end-start))
			[ $loglevel -ge 0 ] && echo "done. duration: $runtime""s.                             "

			EXTENSION=".png"
			INTERMEDIATE="$INTERMEDIATE_OUTPUT_FOLDER/converted""_00001_""${EXTENSION}"

			if [ -e "$INTERMEDIATE" ] && [ -s "$INTERMEDIATE" ] ; then
				mv -vf -- "$INTERMEDIATE" "$target_img"
				echo -e $"\e[92mstep done.\e[0m"
			else
				echo -e $"\e[91mError:\e[0m Step failed. $INTERMEDIATE missing or zero-length."
				mkdir -p input/vr/tasks/$TASKNAME/error
				mv -- $ORIGINALINPUT input/vr/tasks/$TASKNAME/error
				exit 1
			fi
		done
	done

	# SECTION: generate video segements based transformed images according to work plan using configured IV2V workflow.
	# chunk_index: global counter for produced video chunks (one or two per segment)
	chunk_index=0
	for d in "$INTERMEDIATE_INPUT_FOLDER"/segment-*; do
		if [ ! -d "$d" ]; then
			# no segments found (glob didn't match)
			break
		fi
		seg_index=${d##*-}
		# Get frame count for this segment from workplan.json (1-based field index)
		next_index=$((seg_index + 1))
		if [ -e "$WORKPLAN_FILE" ]; then
			framecounts=$(grep -o '"segments_framecount"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$WORKPLAN_FILE" | sed -E 's/.*\[([^]]*)\].*/\1/')
			if [ -n "$framecounts" ]; then
				num_frames=$(echo "$framecounts" | cut -d',' -f$next_index | tr -d '[:space:]')
			else
				num_frames="?"
			fi
		else
			num_frames="?"
		fi
		# first/last generated images from previous step
		first_img="$INTERMEDIATE_INPUT_FOLDER/first_${seg_index}.png"
		last_img="$INTERMEDIATE_INPUT_FOLDER/last_${seg_index}.png"

		# Check contiguity early: while processing the current segment, test whether a *following*
		# segment exists and if that next segment's start == this segment's end + 1.
		if [ -e "$WORKPLAN_FILE" ]; then
			starts=$(grep -o '"segments_start"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$WORKPLAN_FILE" | sed -E 's/.*\[([^]]*)\].*/\1/')
			ends=$(grep -o '"segments_end"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$WORKPLAN_FILE" | sed -E 's/.*\[([^]]*)\].*/\1/')
			if [ -n "$starts" ] && [ -n "$ends" ]; then
				# determine total segments (fields count)
				seg_total=1
				if echo "$starts" | grep -q ','; then
					seg_total=$(echo "$starts" | awk -F, '{print NF}')
				fi
				# next field index (1-based) is next_index+1
				check_field=$((next_index + 1))
				trans_frames=0
				if [ "$check_field" -le "$seg_total" ]; then
					# current segment's end (1-based field = next_index)
					cur_end=$(echo "$ends" | cut -d',' -f$next_index | tr -d '[:space:]')
					next_start=$(echo "$starts" | cut -d',' -f$check_field | tr -d '[:space:]')
					if [ -n "$cur_end" ] && [ -n "$next_start" ]; then
						if expr "$cur_end" : '[-0-9]*$' >/dev/null && expr "$next_start" : '[-0-9]*$' >/dev/null ; then
							if [ "$next_start" -eq $((cur_end + 1)) ]; then
								# echo "Contiguous: segment $((seg_index+1)) start ($next_start) == previous end ($cur_end) + 1"
								# Subtract 4 from num_frames for this segment when contiguous.
								if expr "${num_frames:-}" : '[-0-9]*$' >/dev/null ; then
									# ensure numeric and non-negative result
									if [ "$num_frames" -ge 4 ] 2>/dev/null ; then
										trans_frames=0 # set to zero to disable transition frames
										num_frames=$((num_frames - trans_frames))
									else
										num_frames=0
									fi
								fi
							fi
						fi
					fi
				fi
			fi
		fi

		# lfi2v call to generate video segment from first_img to last_img
		if [ "$num_frames" -ge 1 ] 2>/dev/null ; then
			chunk_file="$INTERMEDIATE_INPUT_FOLDER/chunk_${chunk_index}.mp4"
			if [ -e "$chunk_file" ]; then
				echo "Skipping generation; chunk already exists: $chunk_file"
			else
				echo "--- generating video chunk $chunk_index for segment $seg_index -> frames=$num_frames"
				echo "Segment $seg_index: frames=${num_frames} first=${first_img} last=${last_img} -> will write $chunk_file"
				# call the ComfyUI FL2V workflow to create $chunk_file from $first_img .. $last_img and write outputs into INTERMEDIATE_OUTPUT_FOLDER
				img1="$first_img"
				img2="$last_img"

				# generate chunk via iv2v helper
				# determine start frame for this segment from workplan (convert 1-based -> 0-based)
				start_frame=0
				if [ -e "$WORKPLAN_FILE" ]; then
					starts=$(grep -o '"segments_start"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$WORKPLAN_FILE" | sed -E 's/.*\[([^]]*)\].*/\1/')
					if [ -n "$starts" ]; then
						raw_start=$(echo "$starts" | cut -d',' -f$next_index | tr -d '[:space:]')
						if expr "$raw_start" : '[-0-9]*$' >/dev/null ; then
							start_frame=$((raw_start - 1))
							if [ "$start_frame" -lt 0 ] 2>/dev/null ; then
								start_frame=0
							fi
						fi
					fi
				fi
				if ! iv2v_generate "$img1" "$img2" "$chunk_file" "$num_frames" "$start_frame" ""; then
					mkdir -p input/vr/tasks/$TASKNAME/error
					mv -- $ORIGINALINPUT input/vr/tasks/$TASKNAME/error
					exit 1
				fi
			fi
			chunk_index=$((chunk_index+1))
		fi

		# lfi2v call to generate video segment from last_img to first_img_of_next (transition chunk)
		if [ "$trans_frames" -ge 1 ] 2>/dev/null ; then
			chunk_file="$INTERMEDIATE_INPUT_FOLDER/chunk_${chunk_index}.mp4"
			if [ -e "$chunk_file" ]; then
				echo "Skipping transition generation; chunk already exists: $chunk_file"
			else
				echo "--- generating video chunk $chunk_index for segment transition $seg_index/$next_index -> frames=$trans_frames"
				first_img_of_next="$INTERMEDIATE_INPUT_FOLDER/first_${next_index}.png"
				echo "Segment transition: frames=${trans_frames} first=${last_img} last=${first_img_of_next} -> will write $chunk_file"
				# call the ComfyUI FL2V workflow to create $chunk_file from $last_img .. $first_img_of_next and write outputs into INTERMEDIATE_OUTPUT_FOLDER
				img1="$last_img"
				img2="$first_img_of_next"

				# generate chunk via iv2v helper (transition)
				# determine start frame for transition chunk (convert to 0-based): start0 = cur_end - trans_frames
				start_frame=0
				if [ -e "$WORKPLAN_FILE" ]; then
					ends=$(grep -o '"segments_end"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$WORKPLAN_FILE" | sed -E 's/.*\[([^]]*)\].*/\1/')
					if [ -n "$ends" ]; then
						cur_end=$(echo "$ends" | cut -d',' -f$next_index | tr -d '[:space:]')
						if expr "$cur_end" : '[-0-9]*$' >/dev/null ; then
							start_frame=$((cur_end - trans_frames))
							if [ "$start_frame" -lt 0 ] 2>/dev/null ; then
								start_frame=0
							fi
						fi
					fi
				fi
				if ! iv2v_generate "$img1" "$control_chunk" "$chunk_file" "$trans_frames" "$start_frame" ""; then
					mkdir -p input/vr/tasks/$TASKNAME/error
					mv -- $ORIGINALINPUT input/vr/tasks/$TASKNAME/error
					exit 1
				fi
			fi
			chunk_index=$((chunk_index+1))
		fi

	done

	# SECTION: concat video segements to final video, and apply audio from source video.

	# Build concat list from chunk_*.mp4 in numeric order (chunk_0, chunk_1, ...)
	concat_list="$INTERMEDIATE_INPUT_FOLDER/concat_list.txt"
	rm -f "$concat_list"
	i=0
	found=0
	while : ; do
		chunk="$INTERMEDIATE_INPUT_FOLDER/chunk_${i}.mp4"
		if [ -f "$chunk" ]; then
			# write basename only so ffmpeg resolves the file relative to the concat file directory
			echo "file '$(basename "$chunk")'" >> "$concat_list"
			found=1
			i=$((i+1))
		else
			break
		fi
	done

	if [ $found -eq 0 ]; then
		echo -e $"\e[91mError:\e[0m No chunk_*.mp4 files found in $INTERMEDIATE_INPUT_FOLDER."
		mkdir -p input/vr/tasks/$TASKNAME/error
		mv -- "$ORIGINALINPUT" input/vr/tasks/$TASKNAME/error
		exit 1
	fi

	concat_video="$INTERMEDIATE_INPUT_FOLDER/concat_video.mp4"
	rm -f "$concat_video"

	# Try concat with stream copy; fall back to re-encode if that fails
	"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -y -f concat -safe 0 -i "$concat_list" -c copy "$concat_video"
	if [ $? -ne 0 ]; then
		echo "Warning: concat (stream copy) failed, retrying with re-encode"
		"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -y -f concat -safe 0 -i "$concat_list" -c:v libx264 -preset veryfast -crf 18 -c:a copy "$concat_video"
		if [ $? -ne 0 ]; then
			echo -e $"\e[91mError:\e[0m Failed creating concatenated video"
			mkdir -p input/vr/tasks/$TASKNAME/error
			mv -- "$ORIGINALINPUT" input/vr/tasks/$TASKNAME/error
			exit 1
		fi
	fi

	# Final output path
	FINALVIDEO="$FINALTARGETFOLDER/${ORIG_BASENAME%.*}_transformed.mp4"

	# If source has audio, mux it; otherwise just move concat_video
	# Detect audio stream in original input
	audio_exists=0
	"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams a:0 -show_entries stream=index -of csv=p=0 "$ORIGINALINPUT" >/dev/null 2>&1 && audio_exists=1 || audio_exists=0

	if [ $audio_exists -eq 1 ]; then
		# Map video from concat and audio from original; re-encode audio to AAC
		"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -y -i "$concat_video" -i "$ORIGINALINPUT" -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -shortest "$FINALVIDEO"
		if [ $? -ne 0 ]; then
			echo -e $"\e[91mError:\e[0m Failed muxing audio into final video"
			mkdir -p input/vr/tasks/$TASKNAME/error
			mv -- "$ORIGINALINPUT" input/vr/tasks/$TASKNAME/error
			exit 1
		fi
	else
		# No audio: move or copy concat_video to final location
		mkdir -p "$FINALTARGETFOLDER"
		mv -vf -- "$concat_video" "$FINALVIDEO"
	fi

	echo -e $"\e[92mSuccess:\e[0m Final video written -> $FINALVIDEO"
	mkdir -p input/vr/tasks/$TASKNAME/done
	mv -- $ORIGINALINPUT input/vr/tasks/$TASKNAME/done
	rm -rf -- $INTERMEDIATE_INPUT_FOLDER
	rm

fi
exit 0

