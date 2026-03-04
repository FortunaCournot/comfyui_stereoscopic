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

# Find the most recent ComfyUI output file for a given extension.
# ComfyUI may treat filename_prefix as a subfolder (e.g. "converted/").
find_latest_converted() {
	out_folder="$1"
	ext="$2"
	# shellcheck disable=SC2012
	ls -1t "$out_folder"/converted/converted_*"${ext}" "$out_folder"/converted_*"${ext}" 2>/dev/null | head -n1 || true
}

# Wait (best-effort) for a ComfyUI output file to appear and be non-empty.
wait_for_converted() {
	out_folder="$1"
	ext="$2"
	timeout_s=${3:-15}
	step_s=${4:-1}
	elapsed=0
	while [ "$elapsed" -lt "$timeout_s" ]; do
		f=$(find_latest_converted "$out_folder" "$ext")
		if [ -n "$f" ] && [ -s "$f" ]; then
			printf '%s' "$f"
			return 0
		fi
		sleep "$step_s"
		elapsed=$((elapsed + step_s))
	done
	return 1
}

is_int() {
	# returns 0 if $1 is an integer (possibly negative), else 1
	expr "${1:-}" : '[-0-9][0-9]*$' >/dev/null 2>&1
}

format_frames_progress() {
	start_idx="$1"
	count="$2"
	total="$3"
	if is_int "$start_idx" && is_int "$count" && [ "$count" -ge 1 ] 2>/dev/null; then
		end_idx=$((start_idx + count - 1))
		if is_int "$total" && [ "$total" -ge 1 ] 2>/dev/null; then
			echo "frames ${start_idx} to ${end_idx} of ${total} (count: ${count})"
		else
			echo "frames ${start_idx} to ${end_idx} (count: ${count})"
		fi
		return 0
	fi
	if is_int "$count" && [ "$count" -ge 1 ] 2>/dev/null; then
		echo "frames (count: ${count})"
		return 0
	fi
	return 1
}

# Extract timeout (seconds) from blueprint JSON; supports numeric and quoted numeric.
extract_timeout() {
	json_file="$1"
	[ -f "$json_file" ] || return 0
	line=$(grep -oE '"timeout"[[:space:]]*:[[:space:]]*"?[0-9]+"?' "$json_file" | head -n1 || true)
	[ -n "$line" ] || return 0
	val=$(printf '%s' "$line" | sed -E 's/.*:[[:space:]]*"?([0-9]+)"?/\1/')
	printf '%s' "$val"
}

# Extract lorastrength from blueprint JSON; supports float and quoted float.
extract_lorastrength() {
	json_file="$1"
	default_val="1.0"
	[ -f "$json_file" ] || { printf '%s' "$default_val"; return 0; }
	# Match: lorastrength: 1 | 1.0 | "0.75"
	line=$(grep -oE '"lorastrength"[[:space:]]*:[[:space:]]*"?[0-9]+(\.[0-9]+)?"?' "$json_file" | head -n1 || true)
	[ -n "$line" ] || { printf '%s' "$default_val"; return 0; }
	val=$(printf '%s' "$line" | sed -E 's/.*:[[:space:]]*"?([0-9]+(\.[0-9]+)?)"?/\1/')
	# Final sanity: ensure it still looks like a float
	if printf '%s' "$val" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
		printf '%s' "$val"
	else
		printf '%s' "$default_val"
	fi
}

format_hms() {
	_total="$1"
	if ! is_int "${_total:-}"; then
		printf '%s' '??:??:??'
		return 0
	fi
	if [ "$_total" -lt 0 ] 2>/dev/null ; then
		_total=0
	fi
	printf '%02d:%02d:%02d' $((_total/3600)) $((_total%3600/60)) $((_total%60))
}

# -----------------------------------------------------------------------------
# Runtime estimator constants (no file IO)
#
# NOTE:
# The user requested that runtime_estimator.* is temporary and must not be
# loaded/saved. Keep these values as constants in code.
# -----------------------------------------------------------------------------
EST_I2I_REF_FRAMES=48
# AVG_I2I_MS_PER_SEG is interpreted as runtime for EST_I2I_REF_FRAMES frames.
EST_AVG_I2I_MS_PER_SEG=123169
EST_AVG_IV2V_MS_PER_FRAME=4723
# Ratio of non-Comfy time relative to ComfyUI time, per-mille.
EST_AVG_NONCOMFY_PERMIL=7

estimator_load_stats() {
	I2I_REF_FRAMES=${EST_I2I_REF_FRAMES:-48}
	AVG_I2I_MS_PER_SEG=${EST_AVG_I2I_MS_PER_SEG:-0}
	AVG_IV2V_MS_PER_FRAME=${EST_AVG_IV2V_MS_PER_FRAME:-0}
	AVG_NONCOMFY_PERMIL=${EST_AVG_NONCOMFY_PERMIL:-0}
}

estimator_save_stats() {
	# Disabled by design (no persistence).
	return 0
}

# Exponential moving average with alpha=1/5 (integer ms).
ema_update_ms() {
	_old="$1"
	_new="$2"
	if ! is_int "${_old:-}"; then _old=0; fi
	if ! is_int "${_new:-}"; then _new=0; fi
	# new_avg = (4*old + 1*new) / 5
	echo $(( (4*_old + _new) / 5 ))
}

task_record_i2i_runtime() {
	_runtime_s="$1"
	_seg_frames="$2"
	if ! is_int "${_runtime_s:-}"; then return 0; fi
	TASK_I2I_DONE=$((TASK_I2I_DONE + 1))
	TASK_I2I_TIME_S=$((TASK_I2I_TIME_S + _runtime_s))
	if is_int "${_seg_frames:-}" && [ "${_seg_frames:-0}" -gt 0 ] 2>/dev/null; then
		TASK_I2I_DONE_FRAMES=$((TASK_I2I_DONE_FRAMES + _seg_frames))
	else
		# Fallback: treat it as one reference-segment worth of work.
		TASK_I2I_DONE_FRAMES=$((TASK_I2I_DONE_FRAMES + ${I2I_REF_FRAMES:-48}))
		_seg_frames=${I2I_REF_FRAMES:-48}
	fi
	# Do not update/persist estimator averages (constants only).
}

task_mark_i2i_done_no_runtime() {
	_seg_frames="$1"
	TASK_I2I_DONE=$((TASK_I2I_DONE + 1))
	if is_int "${_seg_frames:-}" && [ "${_seg_frames:-0}" -gt 0 ] 2>/dev/null; then
		TASK_I2I_DONE_FRAMES=$((TASK_I2I_DONE_FRAMES + _seg_frames))
	else
		TASK_I2I_DONE_FRAMES=$((TASK_I2I_DONE_FRAMES + ${I2I_REF_FRAMES:-48}))
	fi
}

task_record_iv2v_runtime() {
	_runtime_s="$1"
	_frames="$2"
	if ! is_int "${_runtime_s:-}"; then return 0; fi
	if ! is_int "${_frames:-}" || [ "${_frames:-0}" -le 0 ] 2>/dev/null; then
		TASK_IV2V_TIME_S=$((TASK_IV2V_TIME_S + _runtime_s))
		return 0
	fi
	TASK_IV2V_DONE_FRAMES=$((TASK_IV2V_DONE_FRAMES + _frames))
	TASK_IV2V_TIME_S=$((TASK_IV2V_TIME_S + _runtime_s))
	# Do not update/persist estimator averages (constants only).
}

task_record_noncomfy_runtime() {
	_runtime_s="$1"
	if ! is_int "${_runtime_s:-}"; then return 0; fi
	if [ "${_runtime_s:-0}" -le 0 ] 2>/dev/null; then return 0; fi
	TASK_NONCOMFY_TIME_S=$((TASK_NONCOMFY_TIME_S + _runtime_s))
	# Do not update/persist estimator averages (constants only).
}

task_log_estimator_recommendations() {
	# Print copy/paste-friendly recommendations for the estimator constants.
	# Only on successful runs and only when loglevel > 0.
	if [ "${loglevel:-0}" -le 0 ] 2>/dev/null; then
		return 0
	fi

	ref=${EST_I2I_REF_FRAMES:-48}
	if ! is_int "${ref:-}" || [ "${ref:-0}" -le 0 ] 2>/dev/null; then ref=48; fi

	echo "=== Estimator calibration (suggested constants) ==="
	echo "# Copy into workflow-v2v-transform.sh (Runtime estimator constants section)"
	echo "# Measured this run:"
	echo "#   i2i:    ${TASK_I2I_TIME_S:-0}s over ${TASK_I2I_DONE_FRAMES:-0} frames"
	echo "#   iv2v:   ${TASK_IV2V_TIME_S:-0}s over ${TASK_IV2V_DONE_FRAMES:-0} frames"
	echo "#   noncomfy:${TASK_NONCOMFY_TIME_S:-0}s"
	echo

	# i2i reference segment time
	rec_i2i_ms_ref="${EST_AVG_I2I_MS_PER_SEG:-0}"
	if is_int "${TASK_I2I_TIME_S:-}" && is_int "${TASK_I2I_DONE_FRAMES:-}" \
		&& [ "${TASK_I2I_TIME_S:-0}" -gt 0 ] 2>/dev/null \
		&& [ "${TASK_I2I_DONE_FRAMES:-0}" -gt 0 ] 2>/dev/null; then
		rec_i2i_ms_ref=$(( (TASK_I2I_TIME_S * 1000 * ref) / TASK_I2I_DONE_FRAMES ))
	fi

	# iv2v ms per frame
	rec_iv2v_ms_pf="${EST_AVG_IV2V_MS_PER_FRAME:-0}"
	if is_int "${TASK_IV2V_TIME_S:-}" && is_int "${TASK_IV2V_DONE_FRAMES:-}" \
		&& [ "${TASK_IV2V_TIME_S:-0}" -gt 0 ] 2>/dev/null \
		&& [ "${TASK_IV2V_DONE_FRAMES:-0}" -gt 0 ] 2>/dev/null; then
		rec_iv2v_ms_pf=$(( (TASK_IV2V_TIME_S * 1000) / TASK_IV2V_DONE_FRAMES ))
	fi

	# noncomfy ratio (per-mille)
	rec_noncomfy_permil="${EST_AVG_NONCOMFY_PERMIL:-0}"
	comfy_s=$(( ${TASK_I2I_TIME_S:-0} + ${TASK_IV2V_TIME_S:-0} ))
	if [ "${comfy_s:-0}" -gt 0 ] 2>/dev/null && is_int "${TASK_NONCOMFY_TIME_S:-}"; then
		rec_noncomfy_permil=$(( (TASK_NONCOMFY_TIME_S * 1000) / comfy_s ))
	fi

	echo "EST_I2I_REF_FRAMES=$ref"
	echo "EST_AVG_I2I_MS_PER_SEG=$rec_i2i_ms_ref"
	echo "EST_AVG_IV2V_MS_PER_FRAME=$rec_iv2v_ms_pf"
	echo "EST_AVG_NONCOMFY_PERMIL=$rec_noncomfy_permil"
	echo "=== /Estimator calibration ==="
}

# Estimate remaining seconds for the *whole* task based on ComfyUI-only measurements
# (i2i scaled by workplan framecount using reference-segment timing + iv2v per frame)
# and workplan counts. Non-Comfy work is included only via a learned ratio (noncomfy/comfy).
estimate_task_remaining_s() {
	remaining_ms=0
	# i2i remaining (scaled by frames / I2I_REF_FRAMES)
	if is_int "${WP_I2I_PLANNED_FRAMES:-}" && is_int "${TASK_I2I_DONE_FRAMES:-}"; then
		rem_i2i_frames=$((WP_I2I_PLANNED_FRAMES - TASK_I2I_DONE_FRAMES))
		if [ "$rem_i2i_frames" -lt 0 ] 2>/dev/null ; then rem_i2i_frames=0; fi
		ref=${I2I_REF_FRAMES:-48}
		if ! is_int "${ref:-}" || [ "${ref:-0}" -le 0 ] 2>/dev/null; then ref=48; fi
		i2i_ms_ref=${AVG_I2I_MS_PER_SEG:-0}
		if ! is_int "${i2i_ms_ref:-}" || [ "${i2i_ms_ref:-0}" -le 0 ] 2>/dev/null; then
			# Always provide an estimate (fallback to code constants).
			i2i_ms_ref=${EST_AVG_I2I_MS_PER_SEG:-37720}
		fi
		remaining_ms=$((remaining_ms + (rem_i2i_frames * i2i_ms_ref) / ref ))
	fi
	# iv2v remaining frames
	if is_int "${WP_TOTAL_FRAMES:-}" && is_int "${TASK_IV2V_DONE_FRAMES:-}"; then
		rem_frames=$((WP_TOTAL_FRAMES - TASK_IV2V_DONE_FRAMES))
		if [ "$rem_frames" -lt 0 ] 2>/dev/null ; then rem_frames=0; fi
		iv2v_ms_pf=${AVG_IV2V_MS_PER_FRAME:-0}
		if ! is_int "${iv2v_ms_pf:-}" || [ "${iv2v_ms_pf:-0}" -le 0 ] 2>/dev/null; then
			# Always provide an estimate (fallback to code constants).
			iv2v_ms_pf=${EST_AVG_IV2V_MS_PER_FRAME:-15064}
		fi
		remaining_ms=$((remaining_ms + rem_frames * iv2v_ms_pf))
	fi

	# While a ComfyUI job is in-flight, treat elapsed time within that job as
	# partial completion so ETA decreases continuously during the wait loops.
	if [ -n "${TASK_ACTIVE_KIND:-}" ] && is_int "${TASK_ACTIVE_T0:-}" && is_int "${TASK_ACTIVE_FRAMES:-}"; then
		now=$(date +%s)
		active_elapsed_s=$((now - TASK_ACTIVE_T0))
		if [ "$active_elapsed_s" -lt 0 ] 2>/dev/null ; then active_elapsed_s=0; fi
		active_elapsed_ms=$((active_elapsed_s * 1000))
		active_expected_ms=0
		if [ "${TASK_ACTIVE_KIND:-}" = "i2i" ]; then
			_ref=${I2I_REF_FRAMES:-48}
			if ! is_int "${_ref:-}" || [ "${_ref:-0}" -le 0 ] 2>/dev/null; then _ref=48; fi
			_i2i_ms_ref=${AVG_I2I_MS_PER_SEG:-0}
			if ! is_int "${_i2i_ms_ref:-}" || [ "${_i2i_ms_ref:-0}" -le 0 ] 2>/dev/null; then
				_i2i_ms_ref=${EST_AVG_I2I_MS_PER_SEG:-37720}
			fi
			active_expected_ms=$(( (TASK_ACTIVE_FRAMES * _i2i_ms_ref) / _ref ))
		elif [ "${TASK_ACTIVE_KIND:-}" = "iv2v" ]; then
			_iv2v_ms_pf=${AVG_IV2V_MS_PER_FRAME:-0}
			if ! is_int "${_iv2v_ms_pf:-}" || [ "${_iv2v_ms_pf:-0}" -le 0 ] 2>/dev/null; then
				_iv2v_ms_pf=${EST_AVG_IV2V_MS_PER_FRAME:-15064}
			fi
			active_expected_ms=$(( TASK_ACTIVE_FRAMES * _iv2v_ms_pf ))
		fi
		if [ "$active_expected_ms" -gt 0 ] 2>/dev/null && [ "$active_elapsed_ms" -gt 0 ] 2>/dev/null; then
			deduct_ms=$active_elapsed_ms
			if [ "$deduct_ms" -gt "$active_expected_ms" ] 2>/dev/null; then deduct_ms=$active_expected_ms; fi
			if [ "$remaining_ms" -gt 0 ] 2>/dev/null; then
				remaining_ms=$((remaining_ms - deduct_ms))
				if [ "$remaining_ms" -lt 0 ] 2>/dev/null; then remaining_ms=0; fi
			fi
		fi
	fi
	remaining_s=$(( (remaining_ms + 500) / 1000 ))
	# Apply noncomfy ratio multiplier.
	ratio_permil="${AVG_NONCOMFY_PERMIL:-0}"
	if ! is_int "${ratio_permil:-}"; then ratio_permil=0; fi
	if [ "$ratio_permil" -lt 0 ] 2>/dev/null; then ratio_permil=0; fi
	# If the ratio isn't set for some reason, fall back to code constant.
	if [ "$ratio_permil" -eq 0 ] 2>/dev/null && is_int "${EST_AVG_NONCOMFY_PERMIL:-}"; then
		ratio_permil="${EST_AVG_NONCOMFY_PERMIL:-0}"
	fi
	if [ "$ratio_permil" -le 0 ] 2>/dev/null ; then
		comfy_s=$((TASK_I2I_TIME_S + TASK_IV2V_TIME_S))
		if [ "$comfy_s" -gt 0 ] 2>/dev/null; then
			ratio_permil=$(( TASK_NONCOMFY_TIME_S * 1000 / comfy_s ))
		fi
	fi
	echo $(( remaining_s * (1000 + ratio_permil) / 1000 ))
}

task_progress_suffix() {
	# Only percent and ETA (whole task) as requested.
	now=$(date +%s)
	if ! is_int "${TASK_T0:-}"; then
		printf '%s' ' progress ?% ETA ??:??:??'
		return 0
	fi
	elapsed=$((now - TASK_T0))
	if [ "$elapsed" -lt 0 ] 2>/dev/null ; then elapsed=0; fi
	eta=$(estimate_task_remaining_s)
	if ! is_int "${eta:-}"; then
		printf '%s' ' progress ?% ETA ??:??:??'
		return 0
	fi
	total=$((elapsed + eta))
	if [ "$total" -le 0 ] 2>/dev/null ; then
		printf '%s' ' progress 0% ETA ??:??:??'
		return 0
	fi
	# progress% = 100 * elapsed / (elapsed + eta)
	pct=$(( elapsed * 100 / total ))
	if [ "$pct" -gt 99 ] 2>/dev/null ; then pct=99; fi
	printf ' progress %s%% ETA %s' "$pct" "$(format_hms "$eta")"
}

iv2v_generate() {
	img1="$1"
	img2="$2"
	chunk_file="$3"
	frames_to_generate="$4"
	start="$5"
	# frames_to_generate is a count; compute inclusive end index (0-based)
	end=$((start + frames_to_generate - 1))

	# extract range of frames from VIDEOINTERMEDIATE into control_chunk
	echo "Extracting control chunk $control_chunk from $VIDEOINTERMEDIATE frames $start-$end"
	control_chunk="$INTERMEDIATE_INPUT_FOLDER/control_chunk.mp4"
	control_chunk=`realpath "$control_chunk"`
	[ $loglevel -lt 2 ] &&
	set -x
	nc_t0=$(date +%s)
	"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -y -i "$VIDEOINTERMEDIATE" -vf "select='between(n\,$start\,$end)'" -vsync 0 -c:v libx264 -preset veryfast -crf 18 -an "$control_chunk"
	nc_t1=$(date +%s)
	task_record_noncomfy_runtime $((nc_t1 - nc_t0))
	set +x
	if [ $? -ne 0 ] || [ ! -s "$control_chunk" ]; then
		echo -e $"\e[91mError:\e[0m Failed creating control chunk $control_chunk"
		mkdir -p input/vr/tasks/$TASKNAME/error
		mv -- $ORIGINALINPUT input/vr/tasks/$TASKNAME/error
		exit 0
	fi


	iv2v_api=`cat "$BLUEPRINTCONFIG" | grep -o '"iv2v_api":[^"]*"[^"]*"' | sed -E 's/".*".*"(.*)"/\1/'`
	prompt=`cat "$BLUEPRINTCONFIG" | grep -o '"iv2v_prompt":[^"]*"[^"]*"' | sed -E 's/".*".*"(.*)"/\1/'`
	# optional timeout (seconds) to trigger failover restart of ComfyUI
	timeout=$(extract_timeout "$BLUEPRINTCONFIG")
	img1=`realpath "$img1"`
	# Optional color reference image. Always pass a valid path so the workflow can't
	# accidentally keep a stale/default color image.
	if [ -n "${img2:-}" ] && [ -f "$img2" ]; then
		img2=`realpath "$img2"`
	else
		img2="$img1"
	fi
	[ $loglevel -ge 2 ] && set -x
	"$PYTHON_BIN_PATH"python.exe "$SCRIPTPATH2" "$iv2v_api" "$img1" "$control_chunk" "$INTERMEDIATE_OUTPUT_FOLDER/converted" "$frames_to_generate" "$prompt" "$img2"
	set +x && [ $loglevel -ge 2 ] && set -x

	start=`date +%s`
	end=`date +%s`
	secs=0
	queuecount=""
	TASK_ACTIVE_KIND=iv2v
	TASK_ACTIVE_T0=$start
	TASK_ACTIVE_FRAMES=$frames_to_generate
	until [ "$queuecount" = "0" ]
	do
		sleep 1
		status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
		if [ "$status" = "closed" ] ; then
			echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
			TASK_ACTIVE_KIND=
			TASK_ACTIVE_T0=
			TASK_ACTIVE_FRAMES=
			return 1
		fi
		curl -silent "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json
		queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`

		end=`date +%s`
		secs=$((end-start))
		itertimemsg=`printf '%02d:%02d:%02d' $((secs/3600)) $((secs%3600/60)) $((secs%60))`
		echo -ne "$itertimemsg$(task_progress_suffix)         \r"
		# centralized failover check (sourcing helper on demand)
		if ! (command -v failover_check >/dev/null 2>&1) ; then
		  if [ -f ./custom_nodes/comfyui_stereoscopic/api/tasks/lib_failover.sh ]; then
		    . ./custom_nodes/comfyui_stereoscopic/api/tasks/lib_failover.sh
		  fi
		fi
		if command -v failover_check >/dev/null 2>&1; then
		  if ! failover_check "$timeout" "$secs"; then
		    TASK_ACTIVE_KIND=
		    TASK_ACTIVE_T0=
		    TASK_ACTIVE_FRAMES=
		    return 1
		  fi
		fi
	done
	runtime=$((end-start))
	[ $loglevel -ge 0 ] && echo "done. duration: $runtime""s.                             "
	# Update estimator with this IV2V runtime and produced frames
	task_record_iv2v_runtime "$runtime" "$frames_to_generate"
	TASK_ACTIVE_KIND=
	TASK_ACTIVE_T0=
	TASK_ACTIVE_FRAMES=

	EXTENSION=".mp4"
		# find the most recent converted_*_${EXTENSION} file (ComfyUI may write numbered suffixes)
		# Wait a bit because ComfyUI may finalize writes slightly after queue becomes empty.
		INTERMEDIATE=$(wait_for_converted "$INTERMEDIATE_OUTPUT_FOLDER" "$EXTENSION" 20 1) || true

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
	SCRIPTPATH1=./custom_nodes/comfyui_stereoscopic/api/python/workflow/i2i_transition.py
	SCRIPTPATH2=./custom_nodes/comfyui_stereoscopic/api/python/workflow/iv2v_transition.py

	NOLINE=-ne
	
	export CONFIGFILE
	if [ -e $CONFIGFILE ] ; then
		loglevel=$(awk -F "=" '/loglevel=/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
		[ $loglevel -ge 2 ] && set -x
		[ $loglevel -ge 2 ] && NOLINE="" ; echo $NOLINE
		config_version=$(awk -F "=" '/config_version=/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
		COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST=/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
		COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT=/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
		export COMFYUIHOST COMFYUIPORT
	else
		echo -e $"\e[91mError:\e[0m No config!?"
		exit 0
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

	status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
	if [ "$status" = "closed" ]; then
		echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
		exit 0
	fi

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

	# Optional flag: force start images for every segment (and thus i2i for every segment).
	# Enable by adding e.g. "force_start": true to the task JSON.
	FORCE_START=0
	force_start_raw=$(grep -oE '"force_start"[[:space:]]*:[[:space:]]*(true|false|1|0|"true"|"false"|"1"|"0")' "$BLUEPRINTCONFIG" 2>/dev/null | head -n1 || true)
	if [ -n "$force_start_raw" ]; then
		force_start_val=$(printf '%s' "$force_start_raw" | sed -E 's/^.*:[[:space:]]*//; s/[",[:space:]]//g')
		case "${force_start_val,,}" in
			true|1) FORCE_START=1 ;;
			*) FORCE_START=0 ;;
		esac
	fi

	PROGRESS=" "
	if [ -e input/vr/tasks/BATCHPROGRESS.TXT ]
	then
		PROGRESS=`cat input/vr/tasks/BATCHPROGRESS.TXT`" "
	fi
	regex="[^/]*$"
	echo "========== $PROGRESS"`echo $INPUT | grep -oP "$regex"`" =========="
	
	# --- Global progress/ETA estimator (whole task) ---
	TASK_T0=$(date +%s)
	TASK_I2I_DONE=0
	TASK_I2I_TIME_S=0
	TASK_I2I_DONE_FRAMES=0
	TASK_IV2V_DONE_FRAMES=0
	TASK_IV2V_TIME_S=0
	TASK_NONCOMFY_TIME_S=0
	# workplan-derived planned units (filled after workplan is ready)
	WP_I2I_PLANNED=0
	WP_I2I_PLANNED_FRAMES=0
	WP_TOTAL_FRAMES=0
	WP_CHUNKS_PLANNED=0
	estimator_load_stats
	
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

	# One-time auto-retry for transient failures:
	# Sometimes ComfyUI finishes the queue but the output file appears a moment later.
	# A full re-run usually succeeds because intermediate files are reused.
	retry_once_or_error() {
		msg="$1"
		if [ "${V2V_AUTORETRY_DONE:-0}" != "1" ]; then
			echo "Warning: $msg"
			echo "Retrying this task once (reusing intermediate files)..."
			export V2V_AUTORETRY_DONE=1
			exec /bin/bash "$0" "$BLUEPRINTCONFIG" "$TASKNAME" "$ORIGINALINPUT"
		fi
		echo -e $"\e[91mError:\e[0m $msg (after one retry)"
		mkdir -p "input/vr/tasks/$TASKNAME/error"
		mv -- "$ORIGINALINPUT" "input/vr/tasks/$TASKNAME/error"
		exit 0
	}

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
	# Some ComfyUI workflows treat filename_prefix as a subfolder; create it proactively.
	mkdir -p "$INTERMEDIATE_OUTPUT_FOLDER/converted"

	# create segment helper dir and metadata under segdata with zero-padded index
	sb_dir="$INTERMEDIATE_INPUT_FOLDER/segdata/segment_$(printf "%04d" "$seg_index")"
	mkdir -p "$sb_dir"


	TARGETPREFIX=${INPUT##*/}
	TARGETPREFIX=$INTERMEDIATE_OUTPUT_FOLDER/${TARGETPREFIX%.*}
	EXTENSION="${INPUT##*.}"
	# Use an MP4 intermediate for processing, independent of the input container.
	# Reason: WebM does not support H.264 video; we standardize the pipeline to H.264/MP4.
	# For resume runs, prefer an existing intermediate (mp4 first, then legacy tmp-input.<inputext>).
	VIDEOINTERMEDIATE_MP4=$INTERMEDIATE_INPUT_FOLDER/tmp-input.mp4
	VIDEOINTERMEDIATE_LEGACY=$INTERMEDIATE_INPUT_FOLDER/tmp-input.$EXTENSION
	if [ -n "$REUSE_WORKPLAN" ]; then
		if [ -s "$VIDEOINTERMEDIATE_MP4" ]; then
			VIDEOINTERMEDIATE="$VIDEOINTERMEDIATE_MP4"
		elif [ -s "$VIDEOINTERMEDIATE_LEGACY" ]; then
			VIDEOINTERMEDIATE="$VIDEOINTERMEDIATE_LEGACY"
		else
			VIDEOINTERMEDIATE="$VIDEOINTERMEDIATE_MP4"
		fi
	else
		VIDEOINTERMEDIATE="$VIDEOINTERMEDIATE_MP4"
	fi
	if [ -z "$REUSE_WORKPLAN" ] ; then
		# Re-encode input to a workflow-specific FPS intermediate file to avoid frame-rate issues
		echo "Converting input to $SCENE_WORKFLOW_FPS FPS -> $VIDEOINTERMEDIATE"
		echo "$(task_progress_suffix)"
		nc_t0=$(date +%s)
		# Video-only intermediate: audio is muxed from ORIGINALINPUT at the end of the pipeline.
		"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -y -i "$INPUT" -filter:v "fps=$SCENE_WORKFLOW_FPS" -c:v libx264 -preset veryfast -crf 18 -an "$VIDEOINTERMEDIATE"
		nc_t1=$(date +%s)
		task_record_noncomfy_runtime $((nc_t1 - nc_t0))
		if [ $? -ne 0 ]; then
			echo -e $"\e[91mError:\e[0m ffmpeg failed converting to $SCENE_WORKFLOW_FPS FPS"
			mkdir -p input/vr/tasks/$TASKNAME/error
			mv -- $ORIGINALINPUT input/vr/tasks/$TASKNAME/error
			rm -rf -- $INTERMEDIATE_INPUT_FOLDER
			exit 0
		fi
	fi

	# GC (Gesamtframecount) of the normalized intermediate video.
	GC_FRAMECOUNT=`"$FFMPEGPATHPREFIX"ffprobe -hide_banner -v error -select_streams v:0 -show_entries stream=nb_frames -of csv=p=0 "$VIDEOINTERMEDIATE" 2>/dev/null | head -n1`
	GC_FRAMECOUNT=$(printf '%s' "$GC_FRAMECOUNT" | tr -d '\r' | tr -d '"')
	if ! is_int "$GC_FRAMECOUNT" ; then
		GC_FRAMECOUNT=""
	fi

	echo "=== STEP 1: detect scene changes in the input video and generate a work plan ==="

	if [ -n "$REUSE_WORKPLAN" ] ; then
		# Reuse existing workplan; set paths
		WORKPLAN_FILE="$INTERMEDIATE_INPUT_FOLDER/workplan.json"
		SCENES_FILE="$INTERMEDIATE_INPUT_FOLDER/scenes.txt"
		echo "Reusing existing workplan: $WORKPLAN_FILE"
	else
		# --- Scene detection: produce a list of scene cut times (one value per line)
		# Threshold can be overridden in the config file via SCENEDETECTION_THRESHOLD_DEFAULT
		#SCENE_THRESHOLD=$(awk -F "=" '/SCENEDETECTION_THRESHOLD_DEFAULT=/ {print $2}' $CONFIGFILE)
		#SCENE_THRESHOLD=${SCENE_THRESHOLD:-0.1}
		SCENE_THRESHOLD=0.2
		SCENES_FILE="$INTERMEDIATE_INPUT_FOLDER/scenes.txt"
		echo "Detecting scenes (threshold=$SCENE_THRESHOLD) -> $SCENES_FILE"
		echo "$(task_progress_suffix)"
		nc_t0=$(date +%s)
		"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -y -i "$VIDEOINTERMEDIATE" -filter:v "select='gt(scene,$SCENE_THRESHOLD)',showinfo" -f null - 2>&1 | grep showinfo | grep pts_time:[0-9.]\* -o | grep [0-9.]\* -o > "$SCENES_FILE"
		nc_t1=$(date +%s)
		task_record_noncomfy_runtime $((nc_t1 - nc_t0))
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
		frame_count=$(grep -oP '(?<="nb_frames": ")[^\"]*' $INTERMEDIATE_INPUT_FOLDER/probe.txt | head -n1)
		if [ -z "$frame_count" ]; then
			# fallback: try without lookbehind (older grep)
			frame_count=$(grep -o '"nb_frames"[[:space:]]*:[[:space:]]*"[^"]*"' $INTERMEDIATE_INPUT_FOLDER/probe.txt | sed -E 's/.*"([0-9\/\.]+)".*/\1/' | head -n1)
		fi
		echo "Total frames in video: $frame_count"
		if ! expr "$frame_count" : '[0-9][0-9]*$' >/dev/null 2>&1 ; then
			echo -e $"\e[91mError:\e[0m Could not determine frame count from ffprobe (nb_frames='$frame_count')."
			mkdir -p input/vr/tasks/$TASKNAME/error
			mv -- $ORIGINALINPUT input/vr/tasks/$TASKNAME/error
			exit 0
		fi
		last_frame=$((frame_count - 1))
		# iterate scenes and print each scene time (will be used later to build segments_json)
		# initialize segments arrays: frame counts, start indices, end indices
		segments_framecount_json="["
		segments_start_json="["
		segments_end_json="["
		segments_scenestart_json="["
		is_first_segment=1
		if [ -e "$SCENES_FILE" ]; then
			idx=0
			prev_frame=0
			while IFS= read -r scene_time || [ -n "$scene_time" ]; do
				# compute frame index for the scene time (intermediate video uses $SCENE_WORKFLOW_FPS FPS)
				frame_index=$(awk -v t="$scene_time" -v fps="$SCENE_WORKFLOW_FPS" 'BEGIN{printf "%d", int(t*fps+0.5)}')
				# calculate number of target frames
				scene_frames=$((frame_index - prev_frame))
				echo "Scene frames in video: $scene_frames (time: $scene_time, frame index: $frame_index)"
				# Apply offsets and clamp to valid range.
				idx_a=$((prev_frame + SCENE_OFFSET_START))
				idx_seg_end=$((frame_index - 1 - SCENE_OFFSET_END))
				# clamp to [0..last_frame]
				[ $idx_a -lt 0 ] && idx_a=0
				[ $idx_seg_end -lt 0 ] && idx_seg_end=0
				[ $idx_a -gt $last_frame ] && idx_a=$last_frame
				[ $idx_seg_end -gt $last_frame ] && idx_seg_end=$last_frame
				# compute effective frames after offsets; if empty, skip but still advance prev_frame
				seg_effectiveframes=$((idx_seg_end - idx_a + 1))
				if [ $seg_effectiveframes -lt 1 ] ; then
					prev_frame=$frame_index
					continue
				fi
				seg_frames=$seg_effectiveframes
				# split for SCENE_SEG_MAX_FRAMES
				# track whether this is the first chunk of the current scene
				scene_first_chunk=1
				while [ $seg_effectiveframes -gt $SCENE_SEG_MAX_FRAMES ] ; do
					idx_b=$((idx_a + SCENE_SEG_MAX_FRAMES - 1))
					# append values to arrays: framecount, start, end
						# determine scenestart flag: 1 for the first chunk of this scene, else 0
						if [ $scene_first_chunk -eq 1 ] ; then
							scenestart_val=1
							scene_first_chunk=0
						else
							scenestart_val=0
						fi
						if [ $is_first_segment -eq 1 ] ; then
							is_first_segment=0
							segments_framecount_json="[${SCENE_SEG_MAX_FRAMES}"
							segments_start_json="[${idx_a}"
							segments_end_json="[${idx_b}"
							segments_scenestart_json="[${scenestart_val}"
						else
							segments_framecount_json="${segments_framecount_json},${SCENE_SEG_MAX_FRAMES}"
							segments_start_json="${segments_start_json},${idx_a}"
							segments_end_json="${segments_end_json},${idx_b}"
							segments_scenestart_json="${segments_scenestart_json},${scenestart_val}"
						fi
					idx=$((idx+1))
					seg_effectiveframes=$((seg_effectiveframes - SCENE_SEG_MAX_FRAMES))
					seg_frames=$((seg_frames - SCENE_SEG_MAX_FRAMES))
					echo "  Split segment chunk: start=$idx_a frames=$SCENE_SEG_MAX_FRAMES"
					idx_a=$((idx_a + SCENE_SEG_MAX_FRAMES))
				done
				# append remaining chunk values to arrays (this chunk starts the scene)
					# remaining chunk: it's the first chunk of the scene iff scene_first_chunk==1
					if [ $scene_first_chunk -eq 1 ] ; then
						scenestart_val=1
						scene_first_chunk=0
					else
						scenestart_val=0
					fi
					if [ $is_first_segment -eq 1 ] ; then
						is_first_segment=0
						segments_framecount_json="[${seg_frames}"
						segments_start_json="[${idx_a}"
						segments_end_json="[${idx_seg_end}"
						segments_scenestart_json="[${scenestart_val}"
					else
						segments_framecount_json="${segments_framecount_json},${seg_frames}"
						segments_start_json="${segments_start_json},${idx_a}"
						segments_end_json="${segments_end_json},${idx_seg_end}"
						segments_scenestart_json="${segments_scenestart_json},${scenestart_val}"
					fi
				prev_frame=$frame_index
				echo "  Split segment chunk: start=$idx_a frames=$seg_frames"
				idx=$((idx+1))
			done < "$SCENES_FILE"
			# compute final segment start/end with offsets
			final_start=$((prev_frame + SCENE_OFFSET_START))
			final_end=$((last_frame - SCENE_OFFSET_END))
				# clamp and compute effective final frames
				[ $final_start -lt 0 ] && final_start=0
				[ $final_end -lt 0 ] && final_end=0
				[ $final_start -gt $last_frame ] && final_start=$last_frame
				[ $final_end -gt $last_frame ] && final_end=$last_frame
				seg_effectiveframes=$((final_end - final_start + 1))
				idx_a=$final_start
				echo "Final frames in video: $seg_effectiveframes (frame index: $final_start)"
			# split final segment into chunks of at most SCENE_SEG_MAX_FRAMES
				# treat the final scene similarly: track first-chunk-in-scene
				scene_first_chunk=1
				while [ $seg_effectiveframes -gt $SCENE_SEG_MAX_FRAMES ] ; do
					idx_b=$((idx_a + SCENE_SEG_MAX_FRAMES - 1))
					if [ $scene_first_chunk -eq 1 ] ; then
						scenestart_val=1
						scene_first_chunk=0
					else
						scenestart_val=0
					fi
					if [ $is_first_segment -eq 1 ] ; then
						is_first_segment=0
						segments_framecount_json="[${SCENE_SEG_MAX_FRAMES}"
						segments_start_json="[${idx_a}"
						segments_end_json="[${idx_b}"
						segments_scenestart_json="[${scenestart_val}"
					else
						segments_framecount_json="${segments_framecount_json},${SCENE_SEG_MAX_FRAMES}"
						segments_start_json="${segments_start_json},${idx_a}"
						segments_end_json="${segments_end_json},${idx_b}"
						segments_scenestart_json="${segments_scenestart_json},${scenestart_val}"
					fi
					seg_effectiveframes=$((seg_effectiveframes - SCENE_SEG_MAX_FRAMES))
					echo "  Split segment chunk: start=$idx_a frames=$SCENE_SEG_MAX_FRAMES"
					idx_a=$((idx_a + SCENE_SEG_MAX_FRAMES))
				done
				# append remaining frames (if any) — this chunk is the first of the final scene iff scene_first_chunk==1
				if [ $seg_effectiveframes -gt 0 ] ; then
					idx_seg_end=$((idx_a + seg_effectiveframes - 1))
					if [ $scene_first_chunk -eq 1 ] ; then
						scenestart_val=1
						scene_first_chunk=0
					else
						scenestart_val=0
					fi
					if [ $is_first_segment -eq 1 ] ; then
						is_first_segment=0
						segments_framecount_json="[${seg_effectiveframes}"
						segments_start_json="[${idx_a}"
						segments_end_json="[${idx_seg_end}"
						segments_scenestart_json="[${scenestart_val}"
					else
						segments_framecount_json="${segments_framecount_json},${seg_effectiveframes}"
						segments_start_json="${segments_start_json},${idx_a}"
						segments_end_json="${segments_end_json},${idx_seg_end}"
						segments_scenestart_json="${segments_scenestart_json},${scenestart_val}"
					fi
					echo "  Split segment chunk: start=$idx_a frames=$seg_effectiveframes"
				fi
		else
			echo "(no scenes)"
		fi
		# close segments arrays and write skeleton workplan (scenes filled, segments left empty) and include source
		segments_framecount_json="${segments_framecount_json}]"
		segments_start_json="${segments_start_json}]"
		segments_end_json="${segments_end_json}]"
		segments_scenestart_json="${segments_scenestart_json}]"
		echo "{\"source\": \"${ORIG_BASENAME}\", \"scenes\": $scenes_json, \"segments_framecount\": $segments_framecount_json, \"segments_start\": $segments_start_json, \"segments_end\": $segments_end_json, \"scenestart\": $segments_scenestart_json}" > "$WORKPLAN_FILE"
		echo "Wrote workplan -> $WORKPLAN_FILE"

		# Workplan was regenerated: remove stale extracted images/segment metadata so STEP 3
		# cannot pick up old segment folders that don't match the new plan.
		rm -rf -- "$INTERMEDIATE_INPUT_FOLDER/segdata" 2>/dev/null || true
		rm -f -- "$INTERMEDIATE_INPUT_FOLDER"/start_*.png "$INTERMEDIATE_INPUT_FOLDER"/end_*.png 2>/dev/null || true
		rm -f -- "$INTERMEDIATE_INPUT_FOLDER"/first_*.png "$INTERMEDIATE_INPUT_FOLDER"/last_*.png 2>/dev/null || true
	fi

	if [ -e "$WORKPLAN_FILE" ]; then
		echo "---"
		echo "Workplan ready: $WORKPLAN_FILE"
		cat "$WORKPLAN_FILE"
		echo "---"
	else
		echo -e $"\e[91mError:\e[0m Workplan not found: $WORKPLAN_FILE"
		mkdir -p input/vr/tasks/$TASKNAME/error
		mv -- $ORIGINALINPUT input/vr/tasks/$TASKNAME/error
		rm -rf -- $INTERMEDIATE_INPUT_FOLDER/*
		exit 0
	fi

	echo "=== STEP 2: generate input images according to work plan ==="

	# Prepare loop: read `segments_start`, `segments_end` and `segments_framecount` from workplan and iterate
	# extract numeric lists inside the brackets
	segments_start_vals=$(grep -o '"segments_start"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$WORKPLAN_FILE" | sed -E 's/.*\[([^]]*)\].*/\1/')
	segments_end_vals=$(grep -o '"segments_end"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$WORKPLAN_FILE" | sed -E 's/.*\[([^]]*)\].*/\1/')
	segments_framecount_vals=$(grep -o '"segments_framecount"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$WORKPLAN_FILE" | sed -E 's/.*\[([^]]*)\].*/\1/' 2>/dev/null)
	segments_scenestart_vals=$(grep -o '"scenestart"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$WORKPLAN_FILE" | sed -E 's/.*\[([^]]*)\].*/\1/' 2>/dev/null)
	# Workplan index base detection:
	# - Newer workplans generated by this script store frame indices as 0-based.
	# - Some older workplans may have stored them as 1-based.
	# If we see a literal 0 in segments_start, assume 0-based; otherwise assume 1-based.
	segments_index_base=1
	if echo "$segments_start_vals" | grep -qE '(^|,)[[:space:]]*0([[:space:]]*,|$)'; then
		segments_index_base=0
	fi
	# if start or framecount arrays are empty, treat as none
	if [ -z "$segments_start_vals" ] || [ -z "$segments_framecount_vals" ]; then
		echo "No segments found in $WORKPLAN_FILE"
	else
		# count entries by number of commas (+1)
		seg_count=1
		if echo "$segments_start_vals" | grep -q ','; then
			seg_count=$(echo "$segments_start_vals" | awk -F, '{print NF}')
		fi
		echo "$seg_count segments found in $WORKPLAN_FILE"
		# Workplan totals used for global ETA/progress estimation
		WP_CHUNKS_PLANNED=$seg_count
		WP_TOTAL_FRAMES=0
		WP_I2I_PLANNED=0
		WP_I2I_PLANNED_FRAMES=0
		for _i in $(seq 1 $seg_count); do
			_fc=$(echo "$segments_framecount_vals" | cut -d',' -f$_i | tr -d '[:space:]')
			if is_int "$_fc" && [ "$_fc" -ge 0 ] 2>/dev/null ; then
				WP_TOTAL_FRAMES=$((WP_TOTAL_FRAMES + _fc))
			fi
			# i2i planned segments: all when FORCE_START=1, else only scenestart==1
			if [ "${FORCE_START:-0}" -eq 1 ] 2>/dev/null ; then
				WP_I2I_PLANNED=$((WP_I2I_PLANNED + 1))
				if is_int "$_fc" && [ "$_fc" -gt 0 ] 2>/dev/null; then
					WP_I2I_PLANNED_FRAMES=$((WP_I2I_PLANNED_FRAMES + _fc))
				fi
			else
				_sc=1
				if [ -n "$segments_scenestart_vals" ]; then
					_sc=$(echo "$segments_scenestart_vals" | cut -d',' -f$_i | tr -d '[:space:]')
					_sc=${_sc:-1}
				fi
				if [ "${_sc:-1}" -eq 1 ] 2>/dev/null ; then
					WP_I2I_PLANNED=$((WP_I2I_PLANNED + 1))
					if is_int "$_fc" && [ "$_fc" -gt 0 ] 2>/dev/null; then
						WP_I2I_PLANNED_FRAMES=$((WP_I2I_PLANNED_FRAMES + _fc))
					fi
				fi
			fi
		done
		# iterate by index (1-based fields for cut)
		for idx in $(seq 1 $seg_count); do
			# determine scenestart flag (default 1)
			scenestart=1
			if [ -n "$segments_scenestart_vals" ]; then
				scenestart=$(echo "$segments_scenestart_vals" | cut -d',' -f$idx | tr -d '[:space:]')
				scenestart=${scenestart:-1}
			fi

			start=$(echo "$segments_start_vals" | cut -d',' -f$idx | tr -d '[:space:]')
			# compute end: prefer explicit segments_end if present, else derive from segments_framecount
			if [ -n "$segments_end_vals" ]; then
				end=$(echo "$segments_end_vals" | cut -d',' -f$idx | tr -d '[:space:]')
			else
				# derive end = start + frames - 1
				frames=$(echo "$segments_framecount_vals" | cut -d',' -f$idx | tr -d '[:space:]')
				if expr "$frames" : '[-0-9]*$' >/dev/null 2>&1 && expr "$start" : '[-0-9]*$' >/dev/null 2>&1 ; then
					end=$((start + frames - 1))
				else
					end=$start
				fi
			fi
			seg_index=$((idx-1))
			idx_p=$(printf "%04d" "$seg_index")
			# skip if both images already exist (quiet check at loop start)
			tgt_start_img="$INTERMEDIATE_INPUT_FOLDER/start_${idx_p}.png"
			tgt_end_img="$INTERMEDIATE_INPUT_FOLDER/end_${idx_p}.png"
			if [ -f "$tgt_start_img" ] && [ -f "$tgt_end_img" ]; then
				# already extracted
				continue
			fi
			# Guard against invalid segments (can happen with offsets): end must be >= start.
			if expr "$start" : '[-0-9]*$' >/dev/null 2>&1 && expr "$end" : '[-0-9]*$' >/dev/null 2>&1 ; then
				if [ "$end" -lt "$start" ] 2>/dev/null ; then
					echo "Warning: skipping invalid segment $idx/$seg_count (segment $seg_index): start=$start end=$end"
					continue
				fi
			fi
			echo "Preparing segment $idx/$seg_count (segment $seg_index): start=$start end=$end"
			# create segment helper dir and metadata under segdata with zero-padded index
			sb_dir="$INTERMEDIATE_INPUT_FOLDER/segdata/segment_${idx_p}"
			mkdir -p "$sb_dir"
			# Convert workplan indices to ffmpeg 0-based indices.
			# For 0-based workplans this is a no-op; for 1-based we subtract 1.
			start0=$((start - segments_index_base))
			end0=$((end - segments_index_base))
			if [ "$start0" -lt 0 ] 2>/dev/null ; then start0=0; fi
			if [ "$end0" -lt 0 ] 2>/dev/null ; then end0=0; fi
			echo "$start0" > "$sb_dir/start.txt"
			echo "$end0" > "$sb_dir/end.txt"

			# extract start frame only if scenestart == 1, unless FORCE_START is enabled (ffmpeg expects 0-based index)
			if [ "$scenestart" -eq 1 ] || [ "${FORCE_START:-0}" -eq 1 ] 2>/dev/null; then
				if [ ! -f "$tgt_start_img" ]; then
					nc_t0=$(date +%s)
					"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -loglevel error -y -i "$VIDEOINTERMEDIATE" -vf "select=eq(n\,$start0)" -vframes 1 -q:v 2 "$tgt_start_img"
					nc_t1=$(date +%s)
					task_record_noncomfy_runtime $((nc_t1 - nc_t0))
					if [ $? -ne 0 ]; then
						echo "Warning: failed extracting start frame $start0 for segment $seg_index"
					fi
				fi
			else
				echo "Skipping start image extraction for segment $seg_index (scenestart=$scenestart)"
			fi
		done
	fi

	echo "=== STEP 3: generate transformed images accoording to workplan using the configured i2i workflow via api"
	# Determine total segment count for progress display (prefer workplan-derived seg_count)
	SEG_TOTAL=${seg_count:-0}
	if [ -z "$SEG_TOTAL" ] || [ "$SEG_TOTAL" -eq 0 ] 2>/dev/null ; then
		SEG_TOTAL=0
		for _segdir in "$INTERMEDIATE_INPUT_FOLDER"/segdata/segment_*; do
			[ -d "$_segdir" ] && SEG_TOTAL=$((SEG_TOTAL+1))
		done
	fi
	seg_iter=0
	# Iterate segments and run ComfyUI workflow for start/end images (placeholder)
	for d in "$INTERMEDIATE_INPUT_FOLDER"/segdata/segment_*; do
		if [ ! -d "$d" ]; then
			# no segments found (glob didn't match)
			break
		fi
		seg_iter=$((seg_iter+1))
		base="$(basename "$d")"
		seg_index=${base#segment_}
		# Determine scenestart flag for this segment (default 1).
		# If scenestart != 1, skip i2i unless FORCE_START is enabled.
		scenestart=1
		if [ -n "$segments_scenestart_vals" ]; then
			# seg_index may be zero-padded; compute 1-based field index safely (base-10)
			next_index=$((10#$seg_index + 1))
			scenestart=$(echo "$segments_scenestart_vals" | cut -d',' -f$next_index | tr -d '[:space:]')
			scenestart=${scenestart:-1}
		fi
		if [ "${scenestart:-0}" -ne 1 ] 2>/dev/null && [ "${FORCE_START:-0}" -ne 1 ] 2>/dev/null ; then
			echo "Skipping i2i for segment $seg_index (scenestart=$scenestart)"
			continue
		fi
		seg_start0=$(cat "$d/start.txt" 2>/dev/null | tr -d '\r')
		seg_end0=$(cat "$d/end.txt" 2>/dev/null | tr -d '\r')
		seg_cnt=""
		if is_int "$seg_start0" && is_int "$seg_end0" && [ "$seg_end0" -ge "$seg_start0" ] 2>/dev/null; then
			seg_cnt=$((seg_end0 - seg_start0 + 1))
		fi
		seg_frames_msg=$(format_frames_progress "$seg_start0" "${seg_cnt:-}" "$GC_FRAMECOUNT" 2>/dev/null || true)
		if [ -n "$seg_frames_msg" ]; then
			echo "--- Processing segment ${seg_iter}/${SEG_TOTAL} ($seg_index): $seg_frames_msg"
		else
			echo "--- Processing segment ${seg_iter}/${SEG_TOTAL} ($seg_index)"
		fi
		# check if i2i outputs already exist (first/last filenames); skip if present
		first_img="$INTERMEDIATE_INPUT_FOLDER/first_${seg_index}.png"
		last_img="$INTERMEDIATE_INPUT_FOLDER/last_${seg_index}.png"
		if [ -f "$first_img" ] ; then   # deactivated: && [ -f "$last_img" ]
			# i2i outputs already present for this segment, skip but count towards progress/ETA
			task_mark_i2i_done_no_runtime "${seg_cnt:-}"
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
				exit 0
			fi

			# call the ComfyUI i2i workflow on $img and write outputs into INTERMEDIATE_OUTPUT_FOLDER
			echo "--- running i2i workflow for segment ${seg_iter}/${SEG_TOTAL} ($seg_index) -> $img"

			i2i_api=`cat "$BLUEPRINTCONFIG" | grep -o '"i2i_api":[^"]*"[^"]*"' | sed -E 's/".*".*"(.*)"/\1/'`
			prompt=`cat "$BLUEPRINTCONFIG" | grep -o '"i2i_prompt":[^"]*"[^"]*"' | sed -E 's/".*".*"(.*)"/\1/'`
			prompt=${prompt:-""}
			# optional timeout (seconds) to trigger failover restart of ComfyUI
			timeout=$(extract_timeout "$BLUEPRINTCONFIG")
			lorastrength=$(extract_lorastrength "$BLUEPRINTCONFIG")
			
			INPUT=`realpath "$img"`
			[ $loglevel -lt 2 ] && set -x
			"$PYTHON_BIN_PATH"python.exe $SCRIPTPATH1 "$i2i_api" "$INPUT" "$INTERMEDIATE_OUTPUT_FOLDER/converted" "$lorastrength" "$prompt"
			set +x && [ $loglevel -ge 2 ] && set -x

			start=`date +%s`
			end=`date +%s`
			secs=0
			queuecount=""
			TASK_ACTIVE_KIND=i2i
			TASK_ACTIVE_T0=$start
			TASK_ACTIVE_FRAMES=${seg_cnt:-${I2I_REF_FRAMES:-48}}
			until [ "$queuecount" = "0" ]
			do
				sleep 1
				
				status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
				if test $# -ne 0
				then	
					echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
					TASK_ACTIVE_KIND=
					TASK_ACTIVE_T0=
					TASK_ACTIVE_FRAMES=
					exit 0
				fi
				curl -silent "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json
				queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
			
				end=`date +%s`
				secs=$((end-start))
				itertimemsg=`printf '%02d:%02d:%02d' $((secs/3600)) $((secs%3600/60)) $((secs%60))`
				echo -ne "$itertimemsg$(task_progress_suffix)         \r"
				# centralized failover check (sourcing helper on demand)
				if ! (command -v failover_check >/dev/null 2>&1) ; then
				  if [ -f ./custom_nodes/comfyui_stereoscopic/api/tasks/lib_failover.sh ]; then
				    . ./custom_nodes/comfyui_stereoscopic/api/tasks/lib_failover.sh
				  fi
				fi
				if command -v failover_check >/dev/null 2>&1; then
				  if ! failover_check "$timeout" "$secs"; then
				    TASK_ACTIVE_KIND=
				    TASK_ACTIVE_T0=
				    TASK_ACTIVE_FRAMES=
				    retry_once_or_error "Timeout/failover triggered while waiting for i2i to finish"
				  fi
				fi
			done
			runtime=$((end-start))
			[ $loglevel -ge 0 ] && echo "done. duration: $runtime""s.                             "
			# Update estimator with this i2i runtime
			task_record_i2i_runtime "$runtime" "${seg_cnt:-}"
			TASK_ACTIVE_KIND=
			TASK_ACTIVE_T0=
			TASK_ACTIVE_FRAMES=

			EXTENSION=".png"
			# find most recent converted_*_${EXTENSION} (ComfyUI writes converted_00002_.png etc.)
			INTERMEDIATE=$(wait_for_converted "$INTERMEDIATE_OUTPUT_FOLDER" "$EXTENSION" 20 1) || true

			if [ -e "$INTERMEDIATE" ] && [ -s "$INTERMEDIATE" ] ; then
				mv -vf -- "$INTERMEDIATE" "$target_img"
				echo -e $"\e[92mstep done.\e[0m"
			else
				retry_once_or_error "Step failed (i2i). Output missing or zero-length: $INTERMEDIATE"
			fi
		done
	done

	echo "=== STEP 4: generate video segements based transformed images according to work plan using configured IV2V workflow."
	# Re-detect index base (see STEP 2 comment). Keep local to STEP 4 to be robust.
	segments_index_base_iv2v=1
	if [ -e "$WORKPLAN_FILE" ]; then
		_starts_tmp=$(grep -o '"segments_start"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$WORKPLAN_FILE" | sed -E 's/.*\[([^]]*)\].*/\1/')
		if echo "$_starts_tmp" | grep -qE '(^|,)[[:space:]]*0([[:space:]]*,|$)'; then
			segments_index_base_iv2v=0
		fi
	fi
	# Used to decide when a new scene starts (avoid color bleed across scenes)
	scenestart_vals_iv2v=""
	if [ -e "$WORKPLAN_FILE" ]; then
		scenestart_vals_iv2v=$(grep -o '"scenestart"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$WORKPLAN_FILE" | sed -E 's/.*\[([^]]*)\].*/\1/' 2>/dev/null)
	fi
	# Determine total segment count for progress display (reuse SEG_TOTAL if present)
	SEG_TOTAL_IV2V=${SEG_TOTAL:-0}
	if [ -z "$SEG_TOTAL_IV2V" ] || [ "$SEG_TOTAL_IV2V" -eq 0 ] 2>/dev/null ; then
		SEG_TOTAL_IV2V=0
		for _segdir in "$INTERMEDIATE_INPUT_FOLDER"/segdata/segment_*; do
			[ -d "$_segdir" ] && SEG_TOTAL_IV2V=$((SEG_TOTAL_IV2V+1))
		done
	fi
	# Upper bound estimate: one main chunk + optional transition chunk per segment
	CHUNK_TOTAL_MAX=$((SEG_TOTAL_IV2V * 2))
	seg_iter_iv2v=0
	
	# chunk_index: global counter for produced video chunks (one or two per segment)
	chunk_index=0
	for d in "$INTERMEDIATE_INPUT_FOLDER"/segdata/segment_*; do
		if [ ! -d "$d" ]; then
			# no segments found (glob didn't match)
			break
		fi
		seg_iter_iv2v=$((seg_iter_iv2v+1))
		base="$(basename "$d")"
		seg_index=${base#segment_}
		# Get segment boundaries from workplan.json and compute num_frames from end-start+1.
		# This keeps chunk length invariant even if a different start image exists (force_start).
		next_index=$((10#$seg_index + 1))
		num_frames="?"
		start_frame=0
		end_frame=0
		if [ -e "$WORKPLAN_FILE" ]; then
			starts=$(grep -o '"segments_start"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$WORKPLAN_FILE" | sed -E 's/.*\[([^]]*)\].*/\1/')
			ends=$(grep -o '"segments_end"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$WORKPLAN_FILE" | sed -E 's/.*\[([^]]*)\].*/\1/')
			framecounts=$(grep -o '"segments_framecount"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$WORKPLAN_FILE" | sed -E 's/.*\[([^]]*)\].*/\1/' 2>/dev/null)
			raw_start=$(echo "$starts" | cut -d',' -f$next_index | tr -d '[:space:]')
			raw_end=$(echo "$ends" | cut -d',' -f$next_index | tr -d '[:space:]')
			# Convert to 0-based indices for ffmpeg/control chunk extraction
			if is_int "$raw_start"; then
				start_frame=$((raw_start - segments_index_base_iv2v))
				if [ "$start_frame" -lt 0 ] 2>/dev/null ; then start_frame=0; fi
			fi
			if is_int "$raw_end"; then
				end_frame=$((raw_end - segments_index_base_iv2v))
				if [ "$end_frame" -lt 0 ] 2>/dev/null ; then end_frame=0; fi
			fi
			if is_int "$start_frame" && is_int "$end_frame" && [ "$end_frame" -ge "$start_frame" ] 2>/dev/null; then
				num_frames=$((end_frame - start_frame + 1))
			else
				# Fallback to segments_framecount if segments_end is missing or invalid
				if [ -n "$framecounts" ]; then
					raw_fc=$(echo "$framecounts" | cut -d',' -f$next_index | tr -d '[:space:]')
					if is_int "$raw_fc" && [ "$raw_fc" -ge 0 ] 2>/dev/null ; then
						num_frames=$raw_fc
					fi
				fi
			fi
		else
			echo "Skipping generation; workplan file not found."
			exit 0
		fi
		seg_start0=$(cat "$d/start.txt" 2>/dev/null | tr -d '\r')
		seg_end0=$(cat "$d/end.txt" 2>/dev/null | tr -d '\r')
		seg_cnt=""
		if is_int "$seg_start0" && is_int "$seg_end0" && [ "$seg_end0" -ge "$seg_start0" ] 2>/dev/null; then
			seg_cnt=$((seg_end0 - seg_start0 + 1))
		fi
		seg_frames_msg=$(format_frames_progress "$seg_start0" "${seg_cnt:-}" "$GC_FRAMECOUNT" 2>/dev/null || true)
		if [ -n "$seg_frames_msg" ]; then
			echo "--- Processing segment ${seg_iter_iv2v}/${SEG_TOTAL_IV2V} ($seg_index): $seg_frames_msg"
		else
			echo "--- Processing segment ${seg_iter_iv2v}/${SEG_TOTAL_IV2V} ($seg_index)"
		fi
		# first/last generated images from previous step
		first_img="$INTERMEDIATE_INPUT_FOLDER/first_${seg_index}.png"
		last_img="$INTERMEDIATE_INPUT_FOLDER/last_${seg_index}.png"
		# Determine whether this segment starts a new scene (scenestart==1).
		# For scenestart==1 we must NOT use a fallback from the previous chunk because
		# quality is better when using a freshly generated first image for the segment.
		scenestart_iv2v=1
		if [ -n "$scenestart_vals_iv2v" ]; then
			scenestart_iv2v=$(echo "$scenestart_vals_iv2v" | cut -d',' -f$next_index | tr -d '[:space:]')
			scenestart_iv2v=${scenestart_iv2v:-1}
		fi
		# Ensure trans_frames is always initialized per segment (avoid stale values)
		trans_frames=0
		# If first_img is missing, try to extract the last frame from the previously generated chunk
		if [ ! -f "$first_img" ]; then
			if [ "${scenestart_iv2v:-1}" -eq 1 ] 2>/dev/null ; then
				# Scene-start: do not use previous-chunk fallback. If i2i didn't generate first_img
				# (resume edge case), fall back to the segment's own extracted start image.
				seg_start_img="$INTERMEDIATE_INPUT_FOLDER/start_${seg_index}.png"
				if [ -s "$seg_start_img" ]; then
					echo "Scene-start fallback: using extracted start image for $seg_index -> $seg_start_img"
					cp -f -- "$seg_start_img" "$first_img"
				else
					echo -e $"\e[91mError:\e[0m Missing first image for scene-start segment $seg_index ($base), and start image is also missing: $seg_start_img"
					mkdir -p input/vr/tasks/$TASKNAME/error
					mv -- "$ORIGINALINPUT" input/vr/tasks/$TASKNAME/error
					exit 0
				fi
			fi
			prev_chunk_index=$((chunk_index - 1))
			if [ "$prev_chunk_index" -ge 0 ] 2>/dev/null ; then
				prev_idx_p=$(printf "%04d" "$prev_chunk_index")
				prev_chunk="$INTERMEDIATE_INPUT_FOLDER/chunk_${prev_idx_p}.mp4"
				if [ -f "$prev_chunk" ]; then
					echo "Fallback: extracting first image from last frame of $prev_chunk"
					# use -sseof to seek from end and grab one frame (works for most ffmpeg builds)
					nc_t0=$(date +%s)
					"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -loglevel error -y -sseof -0.1 -i "$prev_chunk" -vframes 1 -q:v 2 "$first_img"
					nc_t1=$(date +%s)
					task_record_noncomfy_runtime $((nc_t1 - nc_t0))
					if [ $? -ne 0 ] || [ ! -s "$first_img" ]; then
						echo "Error: failed extracting fallback first image from $prev_chunk"
						rm -f -- "$first_img" 2>/dev/null || true
						exit 0
					else
						# Ensure extracted image matches desired dimensions from previous step
						idx_p_seg=$(printf "%04d" "$seg_index")
						# prefer dimensions from start image, then last_img, then VIDEOINTERMEDIATE
						if [ -f "$INTERMEDIATE_INPUT_FOLDER/start_${idx_p_seg}.png" ]; then
							ref_img="$INTERMEDIATE_INPUT_FOLDER/start_${idx_p_seg}.png"
						elif [ -f "$last_img" ]; then
							ref_img="$last_img"
						else
							ref_img="$VIDEOINTERMEDIATE"
						fi
						# probe desired dimensions
						dims=`"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$ref_img" 2>/dev/null`
						desired_w=`echo "$dims" | cut -d',' -f1`
						desired_h=`echo "$dims" | cut -d',' -f2`
						if [ -n "$desired_w" ] && [ -n "$desired_h" ]; then
							# probe current extracted image dimensions
							curdims=`"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$first_img" 2>/dev/null`
							cur_w=`echo "$curdims" | cut -d',' -f1`
							cur_h=`echo "$curdims" | cut -d',' -f2`
							if [ "$cur_w" != "$desired_w" ] || [ "$cur_h" != "$desired_h" ]; then
								tmpf="${first_img}.tmp.png"
								"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -loglevel error -y -i "$first_img" -vf "scale=${desired_w}:${desired_h}:flags=lanczos" "$tmpf"
								if [ $? -eq 0 ] && [ -s "$tmpf" ]; then
									mv -vf -- "$tmpf" "$first_img"
								else
									echo "Warning: failed resizing fallback first image to ${desired_w}x${desired_h}"
									rm -f -- "$tmpf" 2>/dev/null || true
								fi
							fi
						fi
					fi
				fi
			fi
		fi

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
								# Contiguous segments: disable transition frames, but DO NOT modify num_frames.
								# Chunk length must stay invariant regardless of which start image exists.
								trans_frames=0
							else
								echo Info: "scene boundary detected. Non-contiguous: segment $((10#$seg_index+1)) start ($next_start) != previous end ($cur_end) + 1"
							fi
						else	
							echo "Error: cur_end or next_start not numeric for contiguity check."
						fi
					else
						echo "Error: could not extract cur_end or next_start for contiguity check."
					fi
				else
					[ ${loglevel:-0} -ge 1 ] && echo "Info: No next segment to check for contiguity (last segment)."
				fi
			else
				echo "Error: Skipping contiguity check; segments_start or segments_end missing in workplan."
			fi
		else
			echo "Error: Skipping generation; workplan file not found."
		fi

		# lfi2v call to generate video segment from first_img to last_img
		if [ "$num_frames" -ge 1 ] 2>/dev/null ; then
			idx_p=$(printf "%04d" "$chunk_index")
			chunk_file="$INTERMEDIATE_INPUT_FOLDER/chunk_${idx_p}.mp4"
			if [ -e "$chunk_file" ]; then
				echo "Skipping generation; chunk already exists: $chunk_file"
			else
				chunk_no=$((chunk_index + 1))
				chunk_frames_msg=$(format_frames_progress "$start_frame" "$num_frames" "$GC_FRAMECOUNT" 2>/dev/null || true)
				if [ -n "$chunk_frames_msg" ]; then
					echo "--- generating video chunk ${idx_p} (${chunk_no}/${CHUNK_TOTAL_MAX}) for segment ${seg_iter_iv2v}/${SEG_TOTAL_IV2V} ($seg_index) -> $chunk_frames_msg"
				else
					echo "--- generating video chunk ${idx_p} (${chunk_no}/${CHUNK_TOTAL_MAX}) for segment ${seg_iter_iv2v}/${SEG_TOTAL_IV2V} ($seg_index) -> frames=$num_frames"
				fi
				echo "Segment $seg_index: frames=${num_frames} first=${first_img} last=${last_img} -> will write $chunk_file"
				# call the ComfyUI FL2V workflow to create $chunk_file from $first_img .. $last_img and write outputs into INTERMEDIATE_OUTPUT_FOLDER
				img1="$first_img"
				# default to first_img for color matching if last_img from previous chunk is missing or a new segment started.
				color_image="$first_img"
				if [ "${scenestart_iv2v:-1}" -ne 1 ] 2>/dev/null ; then
					prev_seg_index=$((10#$seg_index - 1))
					if [ "$prev_seg_index" -ge 0 ] 2>/dev/null ; then
						prev_seg_p=$(printf "%04d" "$prev_seg_index")
						prev_last_img="$INTERMEDIATE_INPUT_FOLDER/last_${prev_seg_p}.png"
						if [ -s "$prev_last_img" ]; then
							color_image="$prev_last_img"
						fi
					fi
				fi
				img2="$color_image"

				# generate chunk via iv2v helper using start_frame/num_frames computed from workplan
				iv2v_generate "$img1" "$img2" "$chunk_file" "$num_frames" "$start_frame"
				rc=$?
				if [ $rc -ne 0 ]; then
					if [ $rc -eq 2 ]; then
						retry_once_or_error "Step failed (iv2v). Output missing or zero-length."
					fi
					mkdir -p input/vr/tasks/$TASKNAME/error
					mv -- $ORIGINALINPUT input/vr/tasks/$TASKNAME/error
					exit 0
				fi
			fi
			chunk_index=$((chunk_index+1))
		else
			echo "Skipping generation; num_frames=$num_frames invalid for segment $seg_index"
		fi

		# lfi2v call to generate video segment from last_img to first_img_of_next (transition chunk)
		if [ "$trans_frames" -ge 1 ] 2>/dev/null ; then
			idx_p=$(printf "%04d" "$chunk_index")
			chunk_file="$INTERMEDIATE_INPUT_FOLDER/chunk_${idx_p}.mp4"
			if [ -e "$chunk_file" ]; then
				echo "Skipping transition generation; chunk already exists: $chunk_file"
			else
				chunk_no=$((chunk_index + 1))
				chunk_frames_msg=$(format_frames_progress "$start_frame" "$trans_frames" "$GC_FRAMECOUNT" 2>/dev/null || true)
				if [ -n "$chunk_frames_msg" ]; then
					echo "--- generating video chunk ${idx_p} (${chunk_no}/${CHUNK_TOTAL_MAX}) for segment transition ${seg_iter_iv2v}/${SEG_TOTAL_IV2V} ($seg_index/$next_index) -> $chunk_frames_msg"
				else
					echo "--- generating video chunk ${idx_p} (${chunk_no}/${CHUNK_TOTAL_MAX}) for segment transition ${seg_iter_iv2v}/${SEG_TOTAL_IV2V} ($seg_index/$next_index) -> frames=$trans_frames"
				fi
				idx_p_next=$(printf "%04d" "$next_index")
				first_img_of_next="$INTERMEDIATE_INPUT_FOLDER/first_${idx_p_next}.png"
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
				iv2v_generate "$img1" "$control_chunk" "$chunk_file" "$trans_frames" "$start_frame" ""
				rc=$?
				if [ $rc -ne 0 ]; then
					if [ $rc -eq 2 ]; then
						retry_once_or_error "Step failed (iv2v transition). Output missing or zero-length."
					fi
					mkdir -p input/vr/tasks/$TASKNAME/error
					mv -- $ORIGINALINPUT input/vr/tasks/$TASKNAME/error
					exit 0
				fi
			fi
			chunk_index=$((chunk_index+1))
		fi

	done
	

	echo "=== STEP 5: concat video segements to final video, and apply audio from source video."
	echo "$(task_progress_suffix)"

	# Build concat list from chunk_*.mp4 in numeric order (chunk_0, chunk_1, ...)
	concat_list="$INTERMEDIATE_INPUT_FOLDER/concat_list.txt"
	rm -f "$concat_list"
	# Pre-count chunks for progress/info (best effort)
	CHUNK_FILES_TOTAL=0
	for _c in "$INTERMEDIATE_INPUT_FOLDER"/chunk_*.mp4; do
		[ -f "$_c" ] && CHUNK_FILES_TOTAL=$((CHUNK_FILES_TOTAL+1))
	done
	i=0
	found=0
	while : ; do
		idx_p=$(printf "%04d" "$i")
		chunk="$INTERMEDIATE_INPUT_FOLDER/chunk_${idx_p}.mp4"
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
		exit 0
	fi

	concat_video="$INTERMEDIATE_INPUT_FOLDER/concat_video.mp4"
	rm -f "$concat_video"

	echo "--- concat_video segments (${CHUNK_FILES_TOTAL} chunks) to $concat_video"

	# Try concat with stream copy; fall back to re-encode if that fails
	set -x
	nc_t0=$(date +%s)
	"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -y -f concat -safe 0 -i "$concat_list" -c copy "$concat_video"
	nc_t1=$(date +%s)
	task_record_noncomfy_runtime $((nc_t1 - nc_t0))
	set +x
	if [ $? -ne 0 ]; then
		echo "Warning: concat (stream copy) failed, retrying with re-encode"
		nc_t0=$(date +%s)
		"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -y -f concat -safe 0 -i "$concat_list" -c:v libx264 -preset veryfast -crf 18 -c:a copy "$concat_video"
		nc_t1=$(date +%s)
		task_record_noncomfy_runtime $((nc_t1 - nc_t0))
		if [ $? -ne 0 ]; then
			echo -e $"\e[91mError:\e[0m Failed creating concatenated video"
			mkdir -p input/vr/tasks/$TASKNAME/error
			mv -- "$ORIGINALINPUT" input/vr/tasks/$TASKNAME/error
			exit 0
		fi
	fi

	# Final output path
	FINALVIDEO="$FINALTARGETFOLDER/${ORIG_BASENAME%.*}_transformed.mp4"

	# If source has audio, mux it; otherwise just move concat_video
	# Detect audio stream index in original input (if any)
	audio_stream_index=`"$FFMPEGPATHPREFIX"ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$ORIGINALINPUT" 2>/dev/null | head -n1`

	echo "--- adding audio to $concat_video"

	if [ -n "$audio_stream_index" ]; then
		# Map video from concat and the first audio stream of the original; re-encode audio to AAC
		set -x
		nc_t0=$(date +%s)
		"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -y -i "$concat_video" -i "$ORIGINALINPUT" -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -shortest "$FINALVIDEO"
		nc_t1=$(date +%s)
		task_record_noncomfy_runtime $((nc_t1 - nc_t0))
		set +x
		if [ $? -ne 0 ]; then
			echo -e $"\e[91mError:\e[0m Failed muxing audio into final video"
			mkdir -p input/vr/tasks/$TASKNAME/error
			mv -- "$ORIGINALINPUT" input/vr/tasks/$TASKNAME/error
			exit 0
		fi
	else
		# No audio: move or copy concat_video to final location
		echo "No audio stream found in source video."
		mkdir -p "$FINALTARGETFOLDER"
		mv -vf -- "$concat_video" "$FINALVIDEO"
	fi

	mkdir -p input/vr/tasks/$TASKNAME/done
	mv -- $ORIGINALINPUT input/vr/tasks/$TASKNAME/done
	rm -rf -- $INTERMEDIATE_INPUT_FOLDER
	rm -rf -- $INTERMEDIATE_OUTPUT_FOLDER
	task_log_estimator_recommendations
	echo -e $"\e[92mSuccess:\e[0m Final video written -> $FINALVIDEO"
fi
exit 0

