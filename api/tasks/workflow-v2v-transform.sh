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

is_float_01() {
	# returns 0 if $1 is a float in [0,1], else 1
	val="${1:-}"
	printf '%s' "$val" | grep -qE '^(0(\.[0-9]+)?|1(\.0+)?)$'
}

blend_images() {
	# blend imgA and imgB into out with weights wa and wb (floats)
	img_a="$1"
	img_b="$2"
	out_img="$3"
	wa="$4"
	wb="$5"
	"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -loglevel error -y \
		-i "$img_a" -i "$img_b" \
		-filter_complex "[0:v]format=rgba[a];[1:v]format=rgba[b];[a][b]blend=all_expr='A*${wa}+B*${wb}',format=rgba" \
		-frames:v 1 "$out_img"
}

reencode_chunk_from_frames() {
	frames_dir="$1"
	fps="$2"
	out_mp4="$3"
	tmp_mp4="${out_mp4}.tmp.mp4"
	rm -f -- "$tmp_mp4" 2>/dev/null || true
	"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -loglevel error -y \
		-framerate "$fps" -start_number 0 -i "$frames_dir/frame_%06d.png" \
		-r "$fps" -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -an "$tmp_mp4"
	if [ $? -ne 0 ] || [ ! -s "$tmp_mp4" ]; then
		rm -f -- "$tmp_mp4" 2>/dev/null || true
		return 1
	fi
	move_replace_with_retry "$tmp_mp4" "$out_mp4" 120 1
}

blend_inner_chunk_boundary_if_needed() {
	prev_chunk="$1"
	next_chunk="$2"
	blend_a="$3"
	fps="$4"

	# Compute other weight (1 - blend_a)
	blend_b=$(awk -v a="$blend_a" 'BEGIN{b=1.0-a; if(b<0)b=0; if(b>1)b=1; printf "%.6f", b}')

	# temp dirs
	work_root="$INTERMEDIATE_INPUT_FOLDER/forced_inner_blend"
	mkdir -p "$work_root" || true
	prev_id=$(basename "$prev_chunk" | sed -E 's/[^0-9]//g')
	next_id=$(basename "$next_chunk" | sed -E 's/[^0-9]//g')
	prev_dir="$work_root/prev_${prev_id}"
	next_dir="$work_root/next_${next_id}"
	rm -rf -- "$prev_dir" "$next_dir" 2>/dev/null || true
	mkdir -p "$prev_dir" "$next_dir"

	# Extract frames (small chunks; simplest robust approach)
	"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -loglevel error -y -i "$prev_chunk" -vsync 0 -start_number 0 "$prev_dir/frame_%06d.png"
	if [ $? -ne 0 ]; then return 1; fi
	"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -loglevel error -y -i "$next_chunk" -vsync 0 -start_number 0 "$next_dir/frame_%06d.png"
	if [ $? -ne 0 ]; then return 1; fi

	prev_count=$(ls -1 "$prev_dir"/frame_*.png 2>/dev/null | wc -l | tr -d '[:space:]')
	next_count=$(ls -1 "$next_dir"/frame_*.png 2>/dev/null | wc -l | tr -d '[:space:]')
	if ! is_int "$prev_count" || ! is_int "$next_count" || [ "$prev_count" -lt 1 ] 2>/dev/null || [ "$next_count" -lt 1 ] 2>/dev/null; then
		return 1
	fi
	prev_last=$((prev_count - 1))
	prev_last_png=$(printf "%s/frame_%06d.png" "$prev_dir" "$prev_last")
	next_first_png="$next_dir/frame_000000.png"
	if [ ! -s "$prev_last_png" ] || [ ! -s "$next_first_png" ]; then
		return 1
	fi

	# Create and replace boundary frames
	blend_prev_last="$work_root/blend_prev_last_${prev_id}_${next_id}.png"
	blend_next_first="$work_root/blend_next_first_${prev_id}_${next_id}.png"
	rm -f -- "$blend_prev_last" "$blend_next_first" 2>/dev/null || true
	prev_last_orig="$work_root/orig_prev_last_${prev_id}_${next_id}.png"
	next_first_orig="$work_root/orig_next_first_${prev_id}_${next_id}.png"
	rm -f -- "$prev_last_orig" "$next_first_orig" 2>/dev/null || true
	# Keep originals so both blends use the same source frames (symmetric blending)
	cp -f -- "$prev_last_png" "$prev_last_orig" || return 1
	cp -f -- "$next_first_png" "$next_first_orig" || return 1

	# prev last: blend_a * prev_last + blend_b * next_first
	blend_images "$prev_last_orig" "$next_first_orig" "$blend_prev_last" "$blend_a" "$blend_b" || return 1
	cp -f -- "$blend_prev_last" "$prev_last_png" || return 1

	# next first: blend_a * next_first + blend_b * prev_last
	blend_images "$next_first_orig" "$prev_last_orig" "$blend_next_first" "$blend_a" "$blend_b" || return 1
	cp -f -- "$blend_next_first" "$next_first_png" || return 1

	# Re-encode both chunks from modified frames
	reencode_chunk_from_frames "$prev_dir" "$fps" "$prev_chunk" || return 1
	reencode_chunk_from_frames "$next_dir" "$fps" "$next_chunk" || return 1

	return 0
}

# Move a file, retrying while the source is locked (common on Windows when
# ComfyUI finalizes writes slightly after the queue becomes empty).
move_with_retry() {
	src="$1"
	dst="$2"
	timeout_s=${3:-120}
	step_s=${4:-1}

	if [ -e "$dst" ] && [ -s "$dst" ]; then
		return 0
	fi

	t0=$(date +%s)
	first=1
	last_err=""
	while true; do
		if [ -e "$dst" ] && [ -s "$dst" ]; then
			return 0
		fi
		if [ ! -e "$src" ]; then
			# If the source disappears but destination is present, treat as success.
			if [ -e "$dst" ] && [ -s "$dst" ]; then
				return 0
			fi
			last_err="source missing: $src"
			break
		fi

		tmp_err=$(mktemp -t mv_err.XXXXXX 2>/dev/null || echo "")
		if [ -n "$tmp_err" ]; then
			if mv -vf -- "$src" "$dst" 2>"$tmp_err"; then
				rm -f -- "$tmp_err"
				return 0
			fi
			last_err=$(cat "$tmp_err" 2>/dev/null || true)
			rm -f -- "$tmp_err"
		else
			# Fallback if mktemp is unavailable.
			if mv -vf -- "$src" "$dst"; then
				return 0
			fi
			last_err="mv failed"
		fi

		if [ "$first" -eq 1 ] 2>/dev/null; then
			first=0
			[ ${loglevel:-0} -ge 2 ] && echo "Waiting for file unlock to move output..."
		fi
		now=$(date +%s)
		elapsed=$((now - t0))
		if [ "$elapsed" -ge "$timeout_s" ] 2>/dev/null; then
			break
		fi
		sleep "$step_s"
	done

	echo "Error: failed to move '$src' -> '$dst' after ${timeout_s}s. ${last_err}" >&2
	return 1
}

# Replace dst with src, retrying while locked. Unlike move_with_retry, this must
# overwrite the destination (used for re-encoding chunks in-place).
move_replace_with_retry() {
	src="$1"
	dst="$2"
	timeout_s=${3:-120}
	step_s=${4:-1}

	if [ ! -e "$src" ]; then
		[ ${loglevel:-0} -ge 1 ] && echo "Error: replace move source missing: $src"
		return 1
	fi

	t0=$(date +%s)
	first=1
	last_err=""
	while true; do
		if mv -vf -- "$src" "$dst" 2>/dev/null; then
			return 0
		fi

		if [ "$first" -eq 1 ] 2>/dev/null; then
			first=0
			[ ${loglevel:-0} -ge 2 ] && echo "Waiting for file unlock to replace output..."
		fi
		now=$(date +%s)
		elapsed=$((now - t0))
		if [ "$elapsed" -ge "$timeout_s" ] 2>/dev/null; then
			break
		fi
		sleep "$step_s"
		# src might have been moved by a concurrent attempt; if dst exists and src is gone, accept success.
		if [ ! -e "$src" ] && [ -e "$dst" ] && [ -s "$dst" ]; then
			return 0
		fi
		last_err="mv failed"
	done

	[ ${loglevel:-0} -ge 1 ] && echo "Error: timed out replacing file after ${timeout_s}s. src=$src dst=$dst last_err=${last_err}"
	return 1
}

is_int() {
	# returns 0 if $1 is an integer (possibly negative), else 1
	# IMPORTANT: keep this fast (called in tight progress/ETA loops). No external commands.
	v="${1:-}"
	case "$v" in
		""|"-") return 1 ;;
		-*)
			v2="${v#-}"
			;;
		*)
			v2="$v"
			;;
	esac
	case "$v2" in
		""|*[!0-9]*) return 1 ;;
		*) return 0 ;;
	esac
}

# Internal caches for fast progress suffix rendering (no file IO).
TASK_PLANNED_MS_CACHE=""
TASK_PLANNED_COMFY_MS_CACHE=""
TASK_PLANNED_NONCOMFY_MS_CACHE=""
TASK_PLANNED_MS_CACHE_READY=0
PROGRESS_SUFFIX_CACHE=""
PROGRESS_SUFFIX_CACHE_T=-1

progress_now_s() {
	# Prefer bash built-in SECONDS (no process spawn). Fallback to epoch seconds.
	if is_int "${SECONDS:-}"; then
		echo "${SECONDS}"
		return 0
	fi
	# bash printf supports %(...)T without spawning a process (if available)
	now=$(printf '%(%s)T' -1 2>/dev/null || true)
	if is_int "${now:-}"; then
		echo "$now"
		return 0
	fi
	date +%s
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

extract_blend_factor() {
	json_file="$1"
	default_val="0.0"
	[ -f "$json_file" ] || { printf '%s' "$default_val"; return 0; }
	# Match: blend_factor: 0.5 | "0.75"
	line=$(grep -oE '"blend_factor"[[:space:]]*:[[:space:]]*"?[0-9]+(\.[0-9]+)?"?' "$json_file" | head -n1 || true)
	[ -n "$line" ] || { printf '%s' "$default_val"; return 0; }
	val=$(printf '%s' "$line" | sed -E 's/.*:[[:space:]]*"?([0-9]+(\.[0-9]+)?)"?/\1/')
	# Final sanity: ensure it looks like a float in [0,1]
	if is_float_01 "$val"; then
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
# Keep these conservative defaults unless you calibrate from a run where
# iv2v/i2i were actually executed for the counted frames (i.e. excluding
# transition chunks and resume/skips).
EST_AVG_I2I_MS_PER_SEG=123169
EST_AVG_IV2V_MS_PER_FRAME=4723
# Fixed per-ComfyUI-request overhead (queue submission + warmup) in ms.
# This is used for smoother in-flight ETA/progress (avoids sudden ETA jumps at the
# beginning of a ComfyUI call), while keeping STEP 3/4 planned totals close to the
# classic per-frame/per-segment model.
EST_AVG_COMFY_CALL_BASE_MS=4000
# Ratio of non-Comfy time relative to ComfyUI time, per-mille.
EST_AVG_NONCOMFY_PERMIL=7
# Minimum planned non-comfy time in ms (covers STEP 5 concat/mux/blend even when
# NONCOMFY_PERMIL is small). Does not affect STEP 3/4 internal split.
EST_AVG_NONCOMFY_MIN_MS=60000

estimator_load_stats() {
	I2I_REF_FRAMES=${EST_I2I_REF_FRAMES:-48}
	AVG_I2I_MS_PER_SEG=${EST_AVG_I2I_MS_PER_SEG:-0}
	AVG_IV2V_MS_PER_FRAME=${EST_AVG_IV2V_MS_PER_FRAME:-0}
	AVG_NONCOMFY_PERMIL=${EST_AVG_NONCOMFY_PERMIL:-0}
	COMFY_CALL_BASE_MS=${EST_AVG_COMFY_CALL_BASE_MS:-0}
	NONCOMFY_MIN_MS=${EST_AVG_NONCOMFY_MIN_MS:-0}
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

get_comfy_corr_permil() {
	# Per-run correction factor for ComfyUI runtime estimates.
	# 1000 = 1.0x. Activates only after at least 1 *measured* ComfyUI call.
	calls=${TASK_COMFY_CALLS_MEASURED:-0}
	if ! is_int "${calls:-}" || [ "${calls:-0}" -le 0 ] 2>/dev/null; then
		echo 1000
		return 0
	fi
	corr=${TASK_COMFY_CORR_PERMIL:-1000}
	if ! is_int "${corr:-}" || [ "${corr:-0}" -le 0 ] 2>/dev/null; then corr=1000; fi
	# Clamp to keep behavior sane.
	if [ "$corr" -lt 200 ] 2>/dev/null; then corr=200; fi
	if [ "$corr" -gt 10000 ] 2>/dev/null; then corr=10000; fi
	echo "$corr"
}

task_update_comfy_corr_from_call() {
	_kind="$1"
	_runtime_s="$2"
	_frames="$3"
	if ! is_int "${_runtime_s:-}" || [ "${_runtime_s:-0}" -le 0 ] 2>/dev/null; then return 0; fi
	if ! is_int "${_frames:-}" || [ "${_frames:-0}" -le 0 ] 2>/dev/null; then return 0; fi

	runtime_ms=$((_runtime_s * 1000))
	base_ms=$(get_comfy_call_base_ms)
	expected_ms=0
	if [ "${_kind:-}" = "i2i" ]; then
		ref=$(get_i2i_ref_frames)
		i2i_ms_ref_eff=$(get_i2i_ms_ref_effective)
		expected_ms=$(( base_ms + (_frames * i2i_ms_ref_eff) / ref ))
	elif [ "${_kind:-}" = "iv2v" ]; then
		iv2v_ms_pf_eff=$(get_iv2v_ms_pf_effective)
		expected_ms=$(( base_ms + (_frames * iv2v_ms_pf_eff) ))
	fi
	if ! is_int "${expected_ms:-}" || [ "${expected_ms:-0}" -le 0 ] 2>/dev/null; then expected_ms=1; fi

	TASK_COMFY_CALLS_MEASURED=$(( ${TASK_COMFY_CALLS_MEASURED:-0} + 1 ))
	TASK_COMFY_CORR_OBS_MS_SUM=$(( ${TASK_COMFY_CORR_OBS_MS_SUM:-0} + runtime_ms ))
	TASK_COMFY_CORR_EST_MS_SUM=$(( ${TASK_COMFY_CORR_EST_MS_SUM:-0} + expected_ms ))
	if [ "${TASK_COMFY_CORR_EST_MS_SUM:-0}" -le 0 ] 2>/dev/null; then
		TASK_COMFY_CORR_PERMIL=1000
	else
		TASK_COMFY_CORR_PERMIL=$(( (TASK_COMFY_CORR_OBS_MS_SUM * 1000) / TASK_COMFY_CORR_EST_MS_SUM ))
	fi

	# Log correction factor (k) once after the first measured call, and again if it
	# changes noticeably. Keep this out of tight loops.
	if [ "${loglevel:-0}" -ge 1 ] 2>/dev/null; then
		corr=$(get_comfy_corr_permil)
		calls=${TASK_COMFY_CALLS_MEASURED:-0}
		last=${TASK_COMFY_CORR_LAST_PRINT_PERMIL:-0}
		if ! is_int "${last:-}"; then last=0; fi
		delta=$((corr - last))
		if [ "$delta" -lt 0 ] 2>/dev/null; then delta=$((0 - delta)); fi
		if [ "${calls:-0}" -eq 1 ] 2>/dev/null || [ "${last:-0}" -eq 0 ] 2>/dev/null || [ "$delta" -ge 100 ] 2>/dev/null; then
			k=$(awk -v p="$corr" 'BEGIN{printf "%.2f", p/1000.0}')
			echo "Info: ETA correction factor k=${k}x (after ${calls} measured ComfyUI calls)"
			TASK_COMFY_CORR_LAST_PRINT_PERMIL=$corr
		fi
	fi
	# Invalidate cached planned ms so ETA reacts immediately after the first call.
	TASK_PLANNED_MS_CACHE_READY=0
}

task_record_i2i_runtime() {
	_runtime_s="$1"
	_seg_frames="$2"
	if ! is_int "${_runtime_s:-}"; then return 0; fi
	# Track min observed comfy call runtime (heuristic for base overhead recommendation).
	if is_int "${TASK_COMFY_MIN_RUNTIME_S:-}" && [ "${TASK_COMFY_MIN_RUNTIME_S:-0}" -gt 0 ] 2>/dev/null; then
		if [ "$_runtime_s" -lt "$TASK_COMFY_MIN_RUNTIME_S" ] 2>/dev/null; then TASK_COMFY_MIN_RUNTIME_S="$_runtime_s"; fi
	else
		TASK_COMFY_MIN_RUNTIME_S="$_runtime_s"
	fi
	TASK_COMFY_CALLS_DONE=$(( ${TASK_COMFY_CALLS_DONE:-0} + 1 ))
	TASK_I2I_DONE=$((TASK_I2I_DONE + 1))
	TASK_I2I_TIME_S=$((TASK_I2I_TIME_S + _runtime_s))
	if is_int "${_seg_frames:-}" && [ "${_seg_frames:-0}" -gt 0 ] 2>/dev/null; then
		TASK_I2I_DONE_FRAMES=$((TASK_I2I_DONE_FRAMES + _seg_frames))
	else
		# Fallback: treat it as one reference-segment worth of work.
		TASK_I2I_DONE_FRAMES=$((TASK_I2I_DONE_FRAMES + ${I2I_REF_FRAMES:-48}))
		_seg_frames=${I2I_REF_FRAMES:-48}
	fi
	# Update per-run correction multiplier based on measured runtime (excludes skips/resumes).
	task_update_comfy_corr_from_call i2i "$_runtime_s" "${_seg_frames:-${I2I_REF_FRAMES:-48}}"
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
	# If frame count is unknown/zero (e.g. transition chunk), treat this as
	# progress-neutral overhead (noncomfy) rather than skewing iv2v ms/frame.
	if ! is_int "${_frames:-}" || [ "${_frames:-0}" -le 0 ] 2>/dev/null; then
		task_record_noncomfy_runtime "$_runtime_s"
		return 0
	fi
	# Track min observed comfy call runtime (heuristic for base overhead recommendation).
	if is_int "${TASK_COMFY_MIN_RUNTIME_S:-}" && [ "${TASK_COMFY_MIN_RUNTIME_S:-0}" -gt 0 ] 2>/dev/null; then
		if [ "$_runtime_s" -lt "$TASK_COMFY_MIN_RUNTIME_S" ] 2>/dev/null; then TASK_COMFY_MIN_RUNTIME_S="$_runtime_s"; fi
	else
		TASK_COMFY_MIN_RUNTIME_S="$_runtime_s"
	fi
	TASK_COMFY_CALLS_DONE=$(( ${TASK_COMFY_CALLS_DONE:-0} + 1 ))
	TASK_IV2V_DONE_CALLS=$(( ${TASK_IV2V_DONE_CALLS:-0} + 1 ))
	TASK_IV2V_DONE_FRAMES=$((TASK_IV2V_DONE_FRAMES + _frames))
	TASK_IV2V_TIME_S=$((TASK_IV2V_TIME_S + _runtime_s))
	# Update per-run correction multiplier based on measured runtime (excludes skips/resumes).
	task_update_comfy_corr_from_call iv2v "$_runtime_s" "$_frames"
	# Do not update/persist estimator averages (constants only).
}

task_mark_iv2v_done_no_runtime() {
	_frames="$1"
	if is_int "${_frames:-}" && [ "${_frames:-0}" -gt 0 ] 2>/dev/null; then
		TASK_IV2V_DONE_CALLS=$(( ${TASK_IV2V_DONE_CALLS:-0} + 1 ))
		TASK_IV2V_DONE_FRAMES=$((TASK_IV2V_DONE_FRAMES + _frames))
	fi
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
	echo "# Plan (this run):"
	echo "#   planned total frames: ${WP_TOTAL_FRAMES:-0}"
	echo "#   planned i2i frames:   ${WP_I2I_PLANNED_FRAMES:-0}"
	echo "#   planned i2i calls:    ${WP_I2I_PLANNED:-0}"
	echo "#   planned iv2v calls:   ${WP_CHUNKS_PLANNED:-0}"
	echo "#"
	echo "# Measured this run (counters):"
	echo "#   i2i:    ${TASK_I2I_TIME_S:-0}s over ${TASK_I2I_DONE_FRAMES:-0} frames"
	echo "#   iv2v:   ${TASK_IV2V_TIME_S:-0}s over ${TASK_IV2V_DONE_FRAMES:-0} frames"
	echo "#   i2i calls done:  ${TASK_I2I_DONE:-0}"
	echo "#   iv2v calls done: ${TASK_IV2V_DONE_CALLS:-0}"
	echo "#   comfy min runtime (heuristic): ${TASK_COMFY_MIN_RUNTIME_S:-0}s"
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

	# comfy base ms (heuristic recommendation based on minimum observed comfy call runtime)
	rec_base_ms="${EST_AVG_COMFY_CALL_BASE_MS:-0}"
	if ! is_int "${rec_base_ms:-}" || [ "${rec_base_ms:-0}" -lt 0 ] 2>/dev/null; then rec_base_ms=0; fi
	# IMPORTANT: min runtime includes actual generation time, so it's only a good proxy
	# for base overhead when the smallest call is *already* short.
	if is_int "${TASK_COMFY_MIN_RUNTIME_S:-}" && [ "${TASK_COMFY_MIN_RUNTIME_S:-0}" -gt 0 ] 2>/dev/null; then
		min_ms=$((TASK_COMFY_MIN_RUNTIME_S * 1000))
		# Only trust it if it looks like overhead-sized (<= 20s). Otherwise keep the default.
		if [ "$min_ms" -le 20000 ] 2>/dev/null; then
			rec_base_ms=$min_ms
		fi
	fi
	if [ "$rec_base_ms" -gt 20000 ] 2>/dev/null; then rec_base_ms=20000; fi

	# noncomfy minimum planned ms
	rec_noncomfy_min_ms="${EST_AVG_NONCOMFY_MIN_MS:-0}"
	if ! is_int "${rec_noncomfy_min_ms:-}" || [ "${rec_noncomfy_min_ms:-0}" -lt 0 ] 2>/dev/null; then rec_noncomfy_min_ms=0; fi

	echo "EST_I2I_REF_FRAMES=$ref"
	echo "EST_AVG_I2I_MS_PER_SEG=$rec_i2i_ms_ref"
	echo "EST_AVG_IV2V_MS_PER_FRAME=$rec_iv2v_ms_pf"
	echo "EST_AVG_COMFY_CALL_BASE_MS=$rec_base_ms"
	echo "EST_AVG_NONCOMFY_PERMIL=$rec_noncomfy_permil"
	echo "EST_AVG_NONCOMFY_MIN_MS=$rec_noncomfy_min_ms"
	echo "=== /Estimator calibration ==="
}

comfyui_is_present() {
	true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT
}

wait_for_comfyui_present() {
	_timeout_s="$1"
	_poll_s="${2:-2}"
	if ! is_int "${_timeout_s:-}" || [ "${_timeout_s:-0}" -le 0 ] 2>/dev/null; then
		_timeout_s=300
	fi
	if ! is_int "${_poll_s:-}" || [ "${_poll_s:-0}" -le 0 ] 2>/dev/null; then
		_poll_s=2
	fi
	_waited=0
	_warned=0
	until comfyui_is_present; do
		if [ "$_warned" -eq 0 ] 2>/dev/null; then
			echo -e $"\e[93mWarning:\e[0m ComfyUI not present. Waiting for $COMFYUIHOST:$COMFYUIPORT to come back..."
			_warned=1
		fi
		sleep "$_poll_s"
		_waited=$((_waited + _poll_s))
		if [ "$_waited" -ge "$_timeout_s" ] 2>/dev/null; then
			return 1
		fi
	done
	[ "$_warned" -eq 1 ] 2>/dev/null && echo "Info: ComfyUI is present again."
	return 0
}

get_comfy_call_base_ms() {
	base_ms="${COMFY_CALL_BASE_MS:-0}"
	if ! is_int "${base_ms:-}" || [ "${base_ms:-0}" -lt 0 ] 2>/dev/null; then
		base_ms="${EST_AVG_COMFY_CALL_BASE_MS:-0}"
	fi
	if ! is_int "${base_ms:-}" || [ "${base_ms:-0}" -lt 0 ] 2>/dev/null; then
		base_ms=0
	fi
	echo "$base_ms"
}

get_noncomfy_min_ms() {
	min_ms="${NONCOMFY_MIN_MS:-0}"
	if ! is_int "${min_ms:-}" || [ "${min_ms:-0}" -lt 0 ] 2>/dev/null; then
		min_ms="${EST_AVG_NONCOMFY_MIN_MS:-0}"
	fi
	if ! is_int "${min_ms:-}" || [ "${min_ms:-0}" -lt 0 ] 2>/dev/null; then
		min_ms=0
	fi
	echo "$min_ms"
}

get_i2i_ms_ref_effective() {
	# Split planned i2i time into base-per-call + variable-per-frame while keeping the
	# total close to the classic model (per-segment reference time).
	ref=$(get_i2i_ref_frames)
	i2i_ms_ref=$(get_i2i_ms_ref)
	base_ms=$(get_comfy_call_base_ms)
	wp_frames=${WP_I2I_PLANNED_FRAMES:-0}
	wp_calls=${WP_I2I_PLANNED:-0}
	if ! is_int "${wp_frames:-}" || [ "${wp_frames:-0}" -le 0 ] 2>/dev/null; then
		echo "$i2i_ms_ref"
		return 0
	fi
	if ! is_int "${wp_calls:-}" || [ "${wp_calls:-0}" -lt 0 ] 2>/dev/null; then wp_calls=0; fi
	if ! is_int "${base_ms:-}" || [ "${base_ms:-0}" -lt 0 ] 2>/dev/null; then base_ms=0; fi
	raw_ms=$(( (wp_frames * i2i_ms_ref) / ref ))
	base_total=$(( wp_calls * base_ms ))
	var_total=$(( raw_ms - base_total ))
	if [ "$var_total" -lt 0 ] 2>/dev/null; then var_total=0; fi
	eff_ref=$(( (var_total * ref) / wp_frames ))
	if [ "$eff_ref" -le 0 ] 2>/dev/null; then eff_ref=1; fi
	echo "$eff_ref"
}

get_iv2v_ms_pf_effective() {
	iv2v_ms_pf=$(get_iv2v_ms_pf)
	base_ms=$(get_comfy_call_base_ms)
	wp_frames=${WP_TOTAL_FRAMES:-0}
	wp_calls=${WP_CHUNKS_PLANNED:-0}
	if ! is_int "${wp_frames:-}" || [ "${wp_frames:-0}" -le 0 ] 2>/dev/null; then
		echo "$iv2v_ms_pf"
		return 0
	fi
	if ! is_int "${wp_calls:-}" || [ "${wp_calls:-0}" -lt 0 ] 2>/dev/null; then wp_calls=0; fi
	if ! is_int "${base_ms:-}" || [ "${base_ms:-0}" -lt 0 ] 2>/dev/null; then base_ms=0; fi
	raw_ms=$(( wp_frames * iv2v_ms_pf ))
	base_total=$(( wp_calls * base_ms ))
	var_total=$(( raw_ms - base_total ))
	if [ "$var_total" -lt 0 ] 2>/dev/null; then var_total=0; fi
	eff_pf=$(( var_total / wp_frames ))
	if [ "$eff_pf" -le 0 ] 2>/dev/null; then eff_pf=1; fi
	echo "$eff_pf"
}

get_ratio_permil() {
	ratio_permil="${AVG_NONCOMFY_PERMIL:-0}"
	if ! is_int "${ratio_permil:-}"; then ratio_permil=0; fi
	if [ "$ratio_permil" -lt 0 ] 2>/dev/null; then ratio_permil=0; fi
	if [ "$ratio_permil" -eq 0 ] 2>/dev/null && is_int "${EST_AVG_NONCOMFY_PERMIL:-}"; then
		ratio_permil="${EST_AVG_NONCOMFY_PERMIL:-0}"
	fi
	if [ "$ratio_permil" -lt 0 ] 2>/dev/null; then ratio_permil=0; fi
	echo "$ratio_permil"
}

get_i2i_ref_frames() {
	ref=${I2I_REF_FRAMES:-48}
	if ! is_int "${ref:-}" || [ "${ref:-0}" -le 0 ] 2>/dev/null; then ref=48; fi
	echo "$ref"
}

get_i2i_ms_ref() {
	i2i_ms_ref=${AVG_I2I_MS_PER_SEG:-0}
	if ! is_int "${i2i_ms_ref:-}" || [ "${i2i_ms_ref:-0}" -le 0 ] 2>/dev/null; then
		i2i_ms_ref=${EST_AVG_I2I_MS_PER_SEG:-0}
	fi
	if ! is_int "${i2i_ms_ref:-}" || [ "${i2i_ms_ref:-0}" -le 0 ] 2>/dev/null; then
		i2i_ms_ref=1
	fi
	echo "$i2i_ms_ref"
}

get_iv2v_ms_pf() {
	iv2v_ms_pf=${AVG_IV2V_MS_PER_FRAME:-0}
	if ! is_int "${iv2v_ms_pf:-}" || [ "${iv2v_ms_pf:-0}" -le 0 ] 2>/dev/null; then
		iv2v_ms_pf=${EST_AVG_IV2V_MS_PER_FRAME:-0}
	fi
	if ! is_int "${iv2v_ms_pf:-}" || [ "${iv2v_ms_pf:-0}" -le 0 ] 2>/dev/null; then
		iv2v_ms_pf=1
	fi
	echo "$iv2v_ms_pf"
}

estimate_task_planned_ms() {
	# Planned ms is constant once WP_* is filled, but we also apply a per-run
	# correction factor after the first measured ComfyUI call.
	corr=$(get_comfy_corr_permil)
	if [ "${TASK_PLANNED_MS_CACHE_READY:-0}" -eq 1 ] 2>/dev/null \
		&& is_int "${TASK_PLANNED_MS_CACHE:-}" \
		&& is_int "${TASK_PLANNED_MS_CACHE_CORR_PERMIL:-}" \
		&& [ "${TASK_PLANNED_MS_CACHE_CORR_PERMIL:-0}" -eq "${corr:-1000}" ] 2>/dev/null; then
		echo "$TASK_PLANNED_MS_CACHE"
		return 0
	fi
	# Weighted plan units in milliseconds: i2i + iv2v + noncomfy share.
	planned_i2i_ms=0
	planned_iv2v_ms=0
	planned_comfy_base_ms=0
	if is_int "${WP_I2I_PLANNED_FRAMES:-}"; then
		ref=$(get_i2i_ref_frames)
		i2i_ms_ref_eff=$(get_i2i_ms_ref_effective)
		base_ms=$(get_comfy_call_base_ms)
		wp_calls=${WP_I2I_PLANNED:-0}
		if ! is_int "${wp_calls:-}" || [ "${wp_calls:-0}" -lt 0 ] 2>/dev/null; then wp_calls=0; fi
		planned_i2i_base=$(( wp_calls * base_ms ))
		planned_i2i_var=$(( (WP_I2I_PLANNED_FRAMES * i2i_ms_ref_eff) / ref ))
		planned_i2i_ms=$(( planned_i2i_base + planned_i2i_var ))
	fi
	if is_int "${WP_TOTAL_FRAMES:-}"; then
		iv2v_ms_pf_eff=$(get_iv2v_ms_pf_effective)
		base_ms=$(get_comfy_call_base_ms)
		wp_calls=${WP_CHUNKS_PLANNED:-0}
		if ! is_int "${wp_calls:-}" || [ "${wp_calls:-0}" -lt 0 ] 2>/dev/null; then wp_calls=0; fi
		planned_iv2v_base=$(( wp_calls * base_ms ))
		planned_iv2v_var=$(( WP_TOTAL_FRAMES * iv2v_ms_pf_eff ))
		planned_iv2v_ms=$(( planned_iv2v_base + planned_iv2v_var ))
	fi
	planned_comfy_ms=$((planned_i2i_ms + planned_iv2v_ms))
	# Apply per-run correction factor to comfy time so ETA adapts quickly on
	# different machines/resolutions.
	if is_int "${corr:-}" && [ "${corr:-1000}" -ne 1000 ] 2>/dev/null; then
		planned_comfy_ms=$(( planned_comfy_ms * corr / 1000 ))
	fi
	ratio_permil=$(get_ratio_permil)
	planned_noncomfy_ms=$(( planned_comfy_ms * ratio_permil / 1000 ))
	min_noncomfy_ms=$(get_noncomfy_min_ms)
	if [ "${planned_comfy_ms:-0}" -gt 0 ] 2>/dev/null && is_int "${min_noncomfy_ms:-}" && [ "${min_noncomfy_ms:-0}" -gt 0 ] 2>/dev/null; then
		if [ "${planned_noncomfy_ms:-0}" -lt "$min_noncomfy_ms" ] 2>/dev/null; then
			planned_noncomfy_ms="$min_noncomfy_ms"
		fi
	fi
	TASK_PLANNED_MS_CACHE=$(( planned_comfy_ms + planned_noncomfy_ms ))
	TASK_PLANNED_COMFY_MS_CACHE=$planned_comfy_ms
	TASK_PLANNED_NONCOMFY_MS_CACHE=$planned_noncomfy_ms
	TASK_PLANNED_MS_CACHE_CORR_PERMIL=${corr:-1000}
	TASK_PLANNED_MS_CACHE_READY=1
	echo "$TASK_PLANNED_MS_CACHE"
}

estimate_task_done_ms() {
	# Plan-done units in milliseconds: only i2i/iv2v workplan-based done + in-flight partial.
	corr=$(get_comfy_corr_permil)
	done_i2i_ms=0
	done_iv2v_ms=0
	if is_int "${TASK_I2I_DONE_FRAMES:-}"; then
		ref=$(get_i2i_ref_frames)
		i2i_ms_ref_eff=$(get_i2i_ms_ref_effective)
		base_ms=$(get_comfy_call_base_ms)
		done_i2i_base=$(( ${TASK_I2I_DONE:-0} * base_ms ))
		done_i2i_var=$(( (TASK_I2I_DONE_FRAMES * i2i_ms_ref_eff) / ref ))
		done_i2i_ms=$(( done_i2i_base + done_i2i_var ))
		if is_int "${corr:-}" && [ "${corr:-1000}" -ne 1000 ] 2>/dev/null; then
			done_i2i_ms=$(( done_i2i_ms * corr / 1000 ))
		fi
	fi
	if is_int "${TASK_IV2V_DONE_FRAMES:-}"; then
		iv2v_ms_pf_eff=$(get_iv2v_ms_pf_effective)
		base_ms=$(get_comfy_call_base_ms)
		done_iv2v_base=$(( ${TASK_IV2V_DONE_CALLS:-0} * base_ms ))
		done_iv2v_var=$(( TASK_IV2V_DONE_FRAMES * iv2v_ms_pf_eff ))
		done_iv2v_ms=$(( done_iv2v_base + done_iv2v_var ))
		if is_int "${corr:-}" && [ "${corr:-1000}" -ne 1000 ] 2>/dev/null; then
			done_iv2v_ms=$(( done_iv2v_ms * corr / 1000 ))
		fi
	fi
	done_ms=$((done_i2i_ms + done_iv2v_ms))

	# In-flight partial (scaled so it remains consistent with final done counters).
	if [ -n "${TASK_ACTIVE_KIND:-}" ] && is_int "${TASK_ACTIVE_FRAMES:-}"; then
		# Prefer SECONDS-based timing (no process spawn). Fallback to epoch seconds.
		active_elapsed_s=""
		if is_int "${TASK_ACTIVE_T0_SECS:-}" && is_int "${SECONDS:-}"; then
			active_elapsed_s=$((SECONDS - TASK_ACTIVE_T0_SECS))
		elif is_int "${TASK_ACTIVE_T0:-}"; then
			now=$(progress_now_s)
			active_elapsed_s=$((now - TASK_ACTIVE_T0))
		fi
		if ! is_int "${active_elapsed_s:-}"; then active_elapsed_s=0; fi
		if [ "$active_elapsed_s" -lt 0 ] 2>/dev/null ; then active_elapsed_s=0; fi
		active_elapsed_ms=$((active_elapsed_s * 1000))
		active_expected_ms=0
		if [ "${TASK_ACTIVE_KIND:-}" = "i2i" ]; then
			ref=$(get_i2i_ref_frames)
			i2i_ms_ref_eff=$(get_i2i_ms_ref_effective)
			base_ms=$(get_comfy_call_base_ms)
			active_expected_ms=$(( base_ms + (TASK_ACTIVE_FRAMES * i2i_ms_ref_eff) / ref ))
		elif [ "${TASK_ACTIVE_KIND:-}" = "iv2v" ]; then
			iv2v_ms_pf_eff=$(get_iv2v_ms_pf_effective)
			base_ms=$(get_comfy_call_base_ms)
			active_expected_ms=$(( base_ms + (TASK_ACTIVE_FRAMES * iv2v_ms_pf_eff) ))
		fi
		if is_int "${corr:-}" && [ "${corr:-1000}" -ne 1000 ] 2>/dev/null && [ "${active_expected_ms:-0}" -gt 0 ] 2>/dev/null; then
			active_expected_ms=$(( active_expected_ms * corr / 1000 ))
		fi
		if [ "$active_expected_ms" -gt 0 ] 2>/dev/null && [ "$active_elapsed_ms" -gt 0 ] 2>/dev/null; then
			add_ms=$active_elapsed_ms
			if [ "$add_ms" -gt "$active_expected_ms" ] 2>/dev/null; then add_ms=$active_expected_ms; fi
			done_ms=$((done_ms + add_ms))
		fi
	fi

	# Non-comfy done work: count only completed ffmpeg/etc steps (recorded as whole-step runtime).
	# This avoids partial progress *during* ffmpeg, but still lets percent reflect completed non-comfy work.
	planned_total_ms=$(estimate_task_planned_ms)
	planned_noncomfy_ms="${TASK_PLANNED_NONCOMFY_MS_CACHE:-0}"
	if is_int "${planned_total_ms:-}" && [ "${planned_total_ms:-0}" -gt 0 ] 2>/dev/null && is_int "${planned_noncomfy_ms:-}"; then
		done_noncomfy_ms=$(( ${TASK_NONCOMFY_TIME_S:-0} * 1000 ))
		if [ "${done_noncomfy_ms:-0}" -lt 0 ] 2>/dev/null; then done_noncomfy_ms=0; fi
		if [ "${done_noncomfy_ms:-0}" -gt "${planned_noncomfy_ms:-0}" ] 2>/dev/null; then done_noncomfy_ms=$planned_noncomfy_ms; fi
		done_ms=$((done_ms + done_noncomfy_ms))
		# Clamp done to planned_total
		if [ "$done_ms" -gt "$planned_total_ms" ] 2>/dev/null; then done_ms=$planned_total_ms; fi
	fi
	echo "$done_ms"
}

estimate_task_remaining_s() {
	planned_ms=$(estimate_task_planned_ms)
	done_ms=$(estimate_task_done_ms)
	if ! is_int "${planned_ms:-}" || [ "${planned_ms:-0}" -le 0 ] 2>/dev/null; then
		echo 0
		return 0
	fi
	if ! is_int "${done_ms:-}"; then done_ms=0; fi
	rem_ms=$((planned_ms - done_ms))
	if [ "$rem_ms" -lt 0 ] 2>/dev/null; then rem_ms=0; fi
	echo $(( (rem_ms + 500) / 1000 ))
}

task_progress_suffix() {
	# Before workplan totals exist, do not print progress/ETA (avoids misleading 100%).
	if ! is_int "${WP_TOTAL_FRAMES:-}" || [ "${WP_TOTAL_FRAMES:-0}" -le 0 ] 2>/dev/null; then
		printf '%s' ''
		return 0
	fi
	# During the very first in-flight ComfyUI call, we do not have any runtime
	# calibration yet. Hide ETA/% to avoid misleading optimism.
	if [ -n "${TASK_ACTIVE_KIND:-}" ]; then
		calls=${TASK_COMFY_CALLS_MEASURED:-0}
		if ! is_int "${calls:-}"; then calls=0; fi
		if [ "${calls:-0}" -le 0 ] 2>/dev/null; then
			printf '%s' ''
			return 0
		fi
	fi
	# Cache suffix for up to 1 second to keep tight loops fast (no repeated recompute).
	now_s=$(progress_now_s)
	if is_int "${now_s:-}" && [ "${now_s:-0}" -eq "${PROGRESS_SUFFIX_CACHE_T:-999999999}" ] 2>/dev/null && [ -n "${PROGRESS_SUFFIX_CACHE:-}" ]; then
		printf '%s' "$PROGRESS_SUFFIX_CACHE"
		return 0
	fi
	# Only percent and ETA (whole task) as requested.
	planned_ms=$(estimate_task_planned_ms)
	done_ms=$(estimate_task_done_ms)
	eta=$(estimate_task_remaining_s)
	if ! is_int "${planned_ms:-}" || [ "${planned_ms:-0}" -le 0 ] 2>/dev/null || ! is_int "${eta:-}"; then
		printf '%s' ' progress ?% ETA ??:??:??'
		return 0
	fi
	if ! is_int "${done_ms:-}"; then done_ms=0; fi
	# progress% = 100 * done / planned
	if [ "$done_ms" -ge "$planned_ms" ] 2>/dev/null && [ -z "${TASK_ACTIVE_KIND:-}" ]; then
		pct=100
	else
		pct=$(( done_ms * 100 / planned_ms ))
		if [ "$pct" -gt 99 ] 2>/dev/null ; then pct=99; fi
	fi
	if [ "$pct" -lt 0 ] 2>/dev/null ; then pct=0; fi
	PROGRESS_SUFFIX_CACHE=$(printf ' progress %s%% ETA %s' "$pct" "$(format_hms "$eta")")
	PROGRESS_SUFFIX_CACHE_T=${now_s:-0}
	printf '%s' "$PROGRESS_SUFFIX_CACHE"
}

iv2v_generate() {
	img1="$1"
	img2="$2"
	chunk_file="$3"
	frames_to_generate="$4"
	start="$5"
	record_frames="${6:-1}"
	# frames_to_generate is a count; compute inclusive end index (0-based)
	end=$((start + frames_to_generate - 1))

	# extract range of frames from VIDEOINTERMEDIATE into control_chunk
	echo "Extracting control chunk $control_chunk from $VIDEOINTERMEDIATE frames $start-$end"
	control_chunk="$INTERMEDIATE_INPUT_FOLDER/control_chunk.mp4"
	control_chunk=`realpath "$control_chunk"`
	nc_t0=$(date +%s)
	"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -y -i "$VIDEOINTERMEDIATE" -vf "select='between(n\,$start\,$end)'" -vsync 0 -c:v libx264 -preset veryfast -crf 18 -an "$control_chunk"
	nc_t1=$(date +%s)
	task_record_noncomfy_runtime $((nc_t1 - nc_t0))
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
	blend_factor=$(extract_blend_factor "$BLUEPRINTCONFIG")
	img1=`realpath "$img1"`
	# Optional color reference image. Always pass a valid path so the workflow can't
	# accidentally keep a stale/default color image.
	if [ -n "${img2:-}" ] && [ -f "$img2" ]; then
		img2=`realpath "$img2"`
	else
		img2="$img1"
	fi
	# If ComfyUI is down, wait for it before submitting.
	if ! comfyui_is_present; then
		if ! wait_for_comfyui_present "${timeout:-300}" 2; then
			return 1
		fi
	fi
	submit_iv2v() {
		"$PYTHON_BIN_PATH"python.exe "$SCRIPTPATH2" "$iv2v_api" "$img1" "$control_chunk" "$INTERMEDIATE_OUTPUT_FOLDER/converted" "$frames_to_generate" "$prompt" "$blend_factor" "$img2"
	}
	submit_iv2v

	start=`date +%s`
	end=`date +%s`
	secs=0
	queuecount=""
	TASK_ACTIVE_KIND=iv2v
	TASK_ACTIVE_T0=$start
	TASK_ACTIVE_T0_SECS=${SECONDS:-}
	if [ "${record_frames:-1}" -eq 1 ] 2>/dev/null; then
		TASK_ACTIVE_FRAMES=$frames_to_generate
	else
		# Transition chunk: do not affect plan-based progress/ETA.
		TASK_ACTIVE_FRAMES=0
	fi
	until [ "$queuecount" = "0" ]
	do
		sleep 1
		status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
		if [ "$status" = "closed" ] ; then
			echo -e $"\e[93mWarning:\e[0m ComfyUI not present. Waiting and retrying current iv2v request..."
			if ! wait_for_comfyui_present "${timeout:-300}" 2; then
				TASK_ACTIVE_KIND=
				TASK_ACTIVE_T0=
				TASK_ACTIVE_T0_SECS=
				TASK_ACTIVE_FRAMES=
				return 1
			fi
			[ ${loglevel:-0} -ge 1 ] && echo "Info: re-submitting iv2v workflow after ComfyUI restart"
			submit_iv2v
			start=`date +%s`
			end=`date +%s`
			secs=0
			queuecount=""
			TASK_ACTIVE_T0=$start
			TASK_ACTIVE_T0_SECS=${SECONDS:-}
			continue
		fi
		if ! curl -sf "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json; then
			echo -e $"\e[93mWarning:\e[0m Failed to query ComfyUI queue. Waiting and retrying current iv2v request..."
			if ! wait_for_comfyui_present "${timeout:-300}" 2; then
				TASK_ACTIVE_KIND=
				TASK_ACTIVE_T0=
				TASK_ACTIVE_T0_SECS=
				TASK_ACTIVE_FRAMES=
				return 1
			fi
			[ ${loglevel:-0} -ge 1 ] && echo "Info: re-submitting iv2v workflow after ComfyUI queue query failure"
			submit_iv2v
			start=`date +%s`
			end=`date +%s`
			secs=0
			queuecount=""
			TASK_ACTIVE_T0=$start
			TASK_ACTIVE_T0_SECS=${SECONDS:-}
			continue
		fi
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
			    TASK_ACTIVE_T0_SECS=
		    TASK_ACTIVE_FRAMES=
		    return 1
		  fi
		fi
	done
	runtime=$((end-start))
	[ $loglevel -ge 0 ] && echo "done. duration: $runtime""s.                             "
	# Update estimator with this IV2V runtime; optionally count frames for plan-based progress.
	if [ "${record_frames:-1}" -eq 1 ] 2>/dev/null; then
		task_record_iv2v_runtime "$runtime" "$frames_to_generate"
	else
		# Transition chunk: progress-neutral overhead.
		task_record_noncomfy_runtime "$runtime"
	fi
	TASK_ACTIVE_KIND=
	TASK_ACTIVE_T0=
	TASK_ACTIVE_T0_SECS=
	TASK_ACTIVE_FRAMES=

	EXTENSION=".mp4"
		# find the most recent converted_*_${EXTENSION} file (ComfyUI may write numbered suffixes)
		# Wait a bit because ComfyUI may finalize writes slightly after queue becomes empty.
		INTERMEDIATE=$(wait_for_converted "$INTERMEDIATE_OUTPUT_FOLDER" "$EXTENSION" 20 1) || true

	if [ -e "$INTERMEDIATE" ] && [ -s "$INTERMEDIATE" ] ; then
		if move_with_retry "$INTERMEDIATE" "$chunk_file" 120 1; then
			echo -e $"\e[92mstep done.\e[0m"
			return 0
		else
			echo -e $"\e[91mError:\e[0m Step failed. Unable to move output (file locked?): $INTERMEDIATE"
			return 2
		fi
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
		# Do not hard-exit: ComfyUI may be starting up or may have crashed and will be restarted.
		# Wait a bit for it to come back so the pipeline can continue.
		if ! wait_for_comfyui_present 300 2; then
			echo -e $"\e[91mError:\e[0m ComfyUI not present after waiting. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
			exit 0
		fi
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

	# Optional flag: FORCE_START (integer).
	# - 0: default behavior (only create startimages / i2i for scenestart segments)
	# - 1: legacy force behavior (create startimages / i2i for every segment)
	# - n>=2: cadence per scene (create startimages / i2i only for segment 1, 1+n, 1+2n, ... within each scene)
	# Enable by adding e.g. "force_start": 1 (or true) to the task JSON.
	FORCE_START=0
	force_start_raw=$(grep -oE '"force_start"[[:space:]]*:[[:space:]]*(true|false|[0-9]+|"true"|"false"|"[0-9]+")' "$BLUEPRINTCONFIG" 2>/dev/null | head -n1 || true)
	if [ -n "$force_start_raw" ]; then
		force_start_val=$(printf '%s' "$force_start_raw" | sed -E 's/^.*:[[:space:]]*//; s/[",[:space:]]//g')
		case "${force_start_val,,}" in
			true) FORCE_START=1 ;;
			false) FORCE_START=0 ;;
			*)
				if is_int "${force_start_val:-}" && [ "${force_start_val:-0}" -ge 0 ] 2>/dev/null; then
					# Normalize to base-10 (avoid bash treating leading zeros as octal).
					FORCE_START=$((10#$force_start_val))
				else
					FORCE_START=0
				fi
				;;
		esac
	fi

	# Optional flag: detect face appearance per frame and refine segment boundaries
	# within the same scene (workplan generation only).
	# Enable by adding e.g. "detect_face_appearance": true to the task JSON.
	DETECT_FACE_APPEARANCE=0
	detect_face_raw=$(grep -oE '"detect_face_appearance"[[:space:]]*:[[:space:]]*(true|false|1|0|"true"|"false"|"1"|"0")' "$BLUEPRINTCONFIG" 2>/dev/null | head -n1 || true)
	if [ -n "$detect_face_raw" ]; then
		detect_face_val=$(printf '%s' "$detect_face_raw" | sed -E 's/^.*:[[:space:]]*//; s/[",[:space:]]//g')
		case "${detect_face_val,,}" in
			true|1) DETECT_FACE_APPEARANCE=1 ;;
			*) DETECT_FACE_APPEARANCE=0 ;;
		esac
	fi
	# Face visibility threshold (float) and stability window (frames)
	FACE_VIS_THRESHOLD=""
	FACE_VIS_STABLE_FRAMES=""
	if [ -n "${CONFIGFILE:-}" ] && [ -f "$CONFIGFILE" ]; then
		FACE_VIS_THRESHOLD=$(awk -F "=" '/^FACE_VIS_THRESHOLD=/ {print $2}' "$CONFIGFILE" 2>/dev/null | head -n1 | tr -d '\r' | tr -d '[:space:]')
		FACE_VIS_STABLE_FRAMES=$(awk -F "=" '/^FACE_VIS_STABLE_FRAMES=/ {print $2}' "$CONFIGFILE" 2>/dev/null | head -n1 | tr -d '\r' | tr -d '[:space:]')
	fi
	FACE_VIS_THRESHOLD=${FACE_VIS_THRESHOLD:-0.5}
	FACE_VIS_STABLE_FRAMES=${FACE_VIS_STABLE_FRAMES:-8}
	if ! is_float_01 "${FACE_VIS_THRESHOLD:-}"; then
		FACE_VIS_THRESHOLD=0.5
	fi
	if ! is_int "${FACE_VIS_STABLE_FRAMES:-}" || [ "${FACE_VIS_STABLE_FRAMES:-0}" -lt 1 ] 2>/dev/null; then
		FACE_VIS_STABLE_FRAMES=8
	fi
	# When FORCE_START=1 (force i2i for every segment), optionally blend boundary frames between contiguous main chunks
	# within the same scene to avoid hard cuts without changing frame count.
	FORCED_INNER_SEG_BLEND=${FORCED_INNER_SEG_BLEND:-0.80}
	if ! is_float_01 "${FORCED_INNER_SEG_BLEND:-}"; then
		FORCED_INNER_SEG_BLEND=0.80
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
	TASK_IV2V_DONE_CALLS=0
	TASK_NONCOMFY_TIME_S=0
	TASK_COMFY_MIN_RUNTIME_S=0
	TASK_COMFY_CALLS_DONE=0
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
		suffix="$(task_progress_suffix)"
		[ -n "$suffix" ] && echo "$suffix"
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
		suffix="$(task_progress_suffix)"
		[ -n "$suffix" ] && echo "$suffix"
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

		# --- Probe total frame count (needed for workplan + optional face visibility processing)
		# last frame index (for final segment). subtract 1 from count so last_frame is zero-based (index of last frame)
		"$FFMPEGPATHPREFIX"ffprobe -hide_banner -v error -select_streams V:0 -show_entries stream=nb_frames -of json -i "$VIDEOINTERMEDIATE" >"$INTERMEDIATE_INPUT_FOLDER/probe.txt"
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

		# Optional: compute per-frame face visibility scores once, outside the scene loop.
		# Output is a text file with one float per line (frame index 0 corresponds to line 1).
		FACE_VIS_FILE=""
		FACE_VIS_AVAILABLE=0
		if [ "${DETECT_FACE_APPEARANCE:-0}" -eq 1 ] 2>/dev/null; then
			GET_POSE_SCRIPT=./custom_nodes/comfyui_stereoscopic/api/python/workflow/get_pose.py
			FACE_VIS_FILE="$INTERMEDIATE_INPUT_FOLDER/face_visibility.txt"
			FACE_VIS_TMP="$FACE_VIS_FILE.tmp"
			echo "Info: detect_face_appearance=1 -> analyzing face visibility per frame (threshold=${FACE_VIS_THRESHOLD}, stable=${FACE_VIS_STABLE_FRAMES})"
			suffix="$(task_progress_suffix)"
			[ -n "$suffix" ] && echo "$suffix"
			nc_t0=$(date +%s)
			# Use --out-file (no shell redirection). Metric is explicit for reproducibility.
			if "$PYTHON_BIN_PATH"python.exe "$GET_POSE_SCRIPT" \
				--format lines \
				--primary-person body \
				--visibility-metric combined_min \
				--conf-threshold 0.1 \
				--score-threshold 0.6 \
				--eye-ratio-min 0.12 \
				--no-progress \
				--resolution 512 \
				--bbox-detector yolox_l.onnx \
				--pose-estimator dw-ll_ucoco_384_bs5.torchscript.pt \
				--out-file "$FACE_VIS_TMP" \
				"$VIDEOINTERMEDIATE" ; then
				if [ -s "$FACE_VIS_TMP" ]; then
					mv -vf -- "$FACE_VIS_TMP" "$FACE_VIS_FILE"
					FACE_VIS_AVAILABLE=1
				else
					echo "Warning: face visibility output is empty; disabling detect_face_appearance." >&2
					rm -f -- "$FACE_VIS_TMP" 2>/dev/null || true
					FACE_VIS_AVAILABLE=0
				fi
			else
				echo "Warning: get_pose.py failed; disabling detect_face_appearance." >&2
				rm -f -- "$FACE_VIS_TMP" 2>/dev/null || true
				FACE_VIS_AVAILABLE=0
			fi
			nc_t1=$(date +%s)
			task_record_noncomfy_runtime $((nc_t1 - nc_t0))
		fi

		# If face visibility contains -1.0 sentinels ("no person detected"), insert those ranges
		# as additional scene-cut timestamps into SCENES_FILE.
		# For each contiguous negative range we add:
		# - timestamp of the first frame of the range (unless it's frame 0)
		# - timestamp of the frame after the range (end+1), if it exists (< frame_count)
		# Then we unique+sort numerically to keep SCENES_FILE monotonically increasing.
		if [ "${FACE_VIS_AVAILABLE:-0}" -eq 1 ] 2>/dev/null && [ -n "${FACE_VIS_FILE:-}" ] && [ -s "${FACE_VIS_FILE:-}" ] && [ -e "${SCENES_FILE:-}" ]; then
			NO_PERSON_CUTS_TMP="$INTERMEDIATE_INPUT_FOLDER/no_person_scene_cuts.tmp.txt"
			NO_PERSON_MERGE_TMP="$SCENES_FILE.merge.tmp"
			awk -v fps="${SCENE_WORKFLOW_FPS}" -v fc="${frame_count}" '
				function emit_time(frame) {
					if(frame<0){return}
					t = frame / fps
					printf "%.6f\n", t
				}
				BEGIN{ re="^-?[0-9]+(\\.[0-9]+)?$"; in=0; start=0; end=0 }
				{
					v=$0
					sub(/\r$/, "", v)
					if(v~re){x=v+0.0}else{x=0.0}
					frame=NR-1
					if(x<0.0){
						if(!in){in=1; start=frame}
						end=frame
					}else{
						if(in){
							emit_time(start)
							nf=end+1
							if(nf<fc){emit_time(nf)}
							in=0
						}
					}
				}
				END{
					if(in){
						emit_time(start)
						nf=end+1
						if(nf<fc){emit_time(nf)}
					}
				}
			' "$FACE_VIS_FILE" 2>/dev/null > "$NO_PERSON_CUTS_TMP" || true
			if [ -s "$NO_PERSON_CUTS_TMP" ]; then
				cat "$SCENES_FILE" "$NO_PERSON_CUTS_TMP" 2>/dev/null |
				awk 'BEGIN{re="^-?[0-9]+(\\.[0-9]+)?$"} {v=$0; sub(/\r$/, "", v); if(v~re){printf "%.6f\n", v+0.0}}' |
				sort -n -u > "$NO_PERSON_MERGE_TMP" || true
				if [ -s "$NO_PERSON_MERGE_TMP" ]; then
					mv -vf -- "$NO_PERSON_MERGE_TMP" "$SCENES_FILE"
					[ ${loglevel:-0} -ge 1 ] && echo "Info: inserted no-person ranges into scenes list -> $SCENES_FILE"
				else
					rm -f -- "$NO_PERSON_MERGE_TMP" 2>/dev/null || true
				fi
			fi
			rm -f -- "$NO_PERSON_CUTS_TMP" 2>/dev/null || true
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

		# Helper: decide an earlier split length within a chunk window based on
		# face visibility (8 bad frames at start, then 8 good frames above threshold).
		face_chunk_split_len() {
			_start_idx="$1"   # 0-based
			_win_len="$2"     # max frames to consider
			_thr="$3"         # float
			_stable="$4"      # int frames
			_file="$5"        # one float per line
			if ! is_int "${_start_idx:-}" || ! is_int "${_win_len:-}" || ! is_int "${_stable:-}" || ! is_float_01 "${_thr:-}"; then
				echo 0
				return 0
			fi
			if [ "${_win_len:-0}" -lt $(( _stable * 2 )) ] 2>/dev/null; then
				echo 0
				return 0
			fi
			start_line=$((_start_idx + 1))
			# Read only the needed window (avoids scanning the full file for every chunk).
			tail -n +"${start_line}" "${_file}" 2>/dev/null | head -n "${_win_len}" |
			awk -v n="${_win_len}" -v thr="${_thr}" -v st="${_stable}" '
			BEGIN { re="^-?[0-9]+(\\.[0-9]+)?$" }
			{
				v=$0
				sub(/\r$/, "", v)
				if(v!~re){a[NR-1]=0.0} else {
					x=v+0.0
					if(x<0.0){x=0.0}
					a[NR-1]=x
				}
				cnt++
			}
			END {
				if(cnt<n){print 0; exit}
				for(i=0;i<st;i++){
					if(!(a[i] < thr)){print 0; exit}
				}
				for(p=st; p<=n-st; p++){
					good=1
					for(j=0;j<st;j++){
						if(!(a[p+j] >= thr)){good=0; break}
					}
					if(good==1){print p; exit}
				}
				print 0
			}
			' 2>/dev/null
		}
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
					chunk_len=$SCENE_SEG_MAX_FRAMES
					# Optional: refine boundary based on face appearance (within-scene).
					if [ "${FACE_VIS_AVAILABLE:-0}" -eq 1 ] 2>/dev/null && [ -n "${FACE_VIS_FILE:-}" ] && [ -s "${FACE_VIS_FILE:-}" ]; then
						cut_len=$(face_chunk_split_len "$idx_a" "$chunk_len" "$FACE_VIS_THRESHOLD" "$FACE_VIS_STABLE_FRAMES" "$FACE_VIS_FILE")
						if is_int "${cut_len:-}" && [ "${cut_len:-0}" -ge "${FACE_VIS_STABLE_FRAMES:-8}" ] 2>/dev/null && [ "${cut_len:-0}" -lt "${chunk_len:-0}" ] 2>/dev/null; then
							chunk_len=$cut_len
							[ ${loglevel:-0} -ge 1 ] && echo "Info: face-appearance split: start=$idx_a chunk_len=$chunk_len (thr=$FACE_VIS_THRESHOLD stable=$FACE_VIS_STABLE_FRAMES)"
						fi
					fi
					# Special case: when FORCE_START is enabled and the first planned segment
					# would be exactly 48 frames, shorten it to 40 so the last 8 frames shift
					# into the next segment. This preserves total frames and only moves the
					# boundary between segment 0 and 1.
					if [ $is_first_segment -eq 1 ] && [ "${FORCE_START:-0}" -ge 1 ] 2>/dev/null && [ "${chunk_len:-0}" -eq 48 ] 2>/dev/null; then
						chunk_len=40
						[ ${loglevel:-0} -ge 1 ] && echo "Info: FORCE_START first segment boundary tweak: 48->40 frames (shift 8 frames into next segment)"
					fi
					idx_b=$((idx_a + chunk_len - 1))
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
							segments_framecount_json="[${chunk_len}"
							segments_start_json="[${idx_a}"
							segments_end_json="[${idx_b}"
							segments_scenestart_json="[${scenestart_val}"
						else
							segments_framecount_json="${segments_framecount_json},${chunk_len}"
							segments_start_json="${segments_start_json},${idx_a}"
							segments_end_json="${segments_end_json},${idx_b}"
							segments_scenestart_json="${segments_scenestart_json},${scenestart_val}"
						fi
					idx=$((idx+1))
					seg_effectiveframes=$((seg_effectiveframes - chunk_len))
					seg_frames=$((seg_frames - chunk_len))
					echo "  Split segment chunk: start=$idx_a frames=$chunk_len"
					idx_a=$((idx_a + chunk_len))
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
					chunk_len=$SCENE_SEG_MAX_FRAMES
					# Optional: refine boundary based on face appearance (within-scene).
					if [ "${FACE_VIS_AVAILABLE:-0}" -eq 1 ] 2>/dev/null && [ -n "${FACE_VIS_FILE:-}" ] && [ -s "${FACE_VIS_FILE:-}" ]; then
						cut_len=$(face_chunk_split_len "$idx_a" "$chunk_len" "$FACE_VIS_THRESHOLD" "$FACE_VIS_STABLE_FRAMES" "$FACE_VIS_FILE")
						if is_int "${cut_len:-}" && [ "${cut_len:-0}" -ge "${FACE_VIS_STABLE_FRAMES:-8}" ] 2>/dev/null && [ "${cut_len:-0}" -lt "${chunk_len:-0}" ] 2>/dev/null; then
							chunk_len=$cut_len
							[ ${loglevel:-0} -ge 1 ] && echo "Info: face-appearance split: start=$idx_a chunk_len=$chunk_len (thr=$FACE_VIS_THRESHOLD stable=$FACE_VIS_STABLE_FRAMES)"
						fi
					fi
					# Same special case for the very first segment overall.
					if [ $is_first_segment -eq 1 ] && [ "${FORCE_START:-0}" -ge 1 ] 2>/dev/null && [ "${chunk_len:-0}" -eq 48 ] 2>/dev/null; then
						chunk_len=40
						[ ${loglevel:-0} -ge 1 ] && echo "Info: FORCE_START first segment boundary tweak: 48->40 frames (shift 8 frames into next segment)"
					fi
					idx_b=$((idx_a + chunk_len - 1))
					if [ $scene_first_chunk -eq 1 ] ; then
						scenestart_val=1
						scene_first_chunk=0
					else
						scenestart_val=0
					fi
					if [ $is_first_segment -eq 1 ] ; then
						is_first_segment=0
						segments_framecount_json="[${chunk_len}"
						segments_start_json="[${idx_a}"
						segments_end_json="[${idx_b}"
						segments_scenestart_json="[${scenestart_val}"
					else
						segments_framecount_json="${segments_framecount_json},${chunk_len}"
						segments_start_json="${segments_start_json},${idx_a}"
						segments_end_json="${segments_end_json},${idx_b}"
						segments_scenestart_json="${segments_scenestart_json},${scenestart_val}"
					fi
					seg_effectiveframes=$((seg_effectiveframes - chunk_len))
					echo "  Split segment chunk: start=$idx_a frames=$chunk_len"
					idx_a=$((idx_a + chunk_len))
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
		# Track segment index within each scene (1-based) for FORCE_START>=2 cadence.
		scene_seg_pos=0
		for _i in $(seq 1 $seg_count); do
			_fc=$(echo "$segments_framecount_vals" | cut -d',' -f$_i | tr -d '[:space:]')
			if is_int "$_fc" && [ "$_fc" -ge 0 ] 2>/dev/null ; then
				WP_TOTAL_FRAMES=$((WP_TOTAL_FRAMES + _fc))
			fi
			_sc=1
			if [ -n "$segments_scenestart_vals" ]; then
				_sc=$(echo "$segments_scenestart_vals" | cut -d',' -f$_i | tr -d '[:space:]')
				_sc=${_sc:-1}
			fi
			if [ "${_sc:-1}" -eq 1 ] 2>/dev/null ; then
				scene_seg_pos=1
			else
				scene_seg_pos=$((scene_seg_pos + 1))
			fi
			# i2i planned segments:
			# - FORCE_START=0: only scenestart segments
			# - FORCE_START=1: all segments
			# - FORCE_START=n>=2: segments 1, 1+n, 1+2n, ... within each scene
			_i2i=0
			if [ "${FORCE_START:-0}" -le 0 ] 2>/dev/null ; then
				if [ "${_sc:-1}" -eq 1 ] 2>/dev/null ; then
					_i2i=1
				fi
			elif [ "${FORCE_START:-0}" -eq 1 ] 2>/dev/null ; then
				_i2i=1
			else
				_mod=$(((scene_seg_pos - 1) % FORCE_START))
				if [ "${_mod:-1}" -eq 0 ] 2>/dev/null ; then
					_i2i=1
				fi
			fi
			if [ "${_i2i:-0}" -eq 1 ] 2>/dev/null ; then
				WP_I2I_PLANNED=$((WP_I2I_PLANNED + 1))
				if is_int "$_fc" && [ "$_fc" -gt 0 ] 2>/dev/null; then
					WP_I2I_PLANNED_FRAMES=$((WP_I2I_PLANNED_FRAMES + _fc))
				fi
			fi
		done
		# iterate by index (1-based fields for cut)
		scene_seg_pos=0
		for idx in $(seq 1 $seg_count); do
			# determine scenestart flag (default 1)
			scenestart=1
			if [ -n "$segments_scenestart_vals" ]; then
				scenestart=$(echo "$segments_scenestart_vals" | cut -d',' -f$idx | tr -d '[:space:]')
				scenestart=${scenestart:-1}
			fi
			if [ "${scenestart:-1}" -eq 1 ] 2>/dev/null ; then
				scene_seg_pos=1
			else
				scene_seg_pos=$((scene_seg_pos + 1))
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

			# Extract start frame according to FORCE_START cadence (ffmpeg expects 0-based index).
			do_start_img=0
			if [ "${FORCE_START:-0}" -le 0 ] 2>/dev/null ; then
				if [ "${scenestart:-0}" -eq 1 ] 2>/dev/null ; then
					do_start_img=1
				fi
			elif [ "${FORCE_START:-0}" -eq 1 ] 2>/dev/null ; then
				do_start_img=1
			else
				_mod=$(((scene_seg_pos - 1) % FORCE_START))
				if [ "${_mod:-1}" -eq 0 ] 2>/dev/null ; then
					do_start_img=1
				fi
			fi
			if [ "${do_start_img:-0}" -eq 1 ] 2>/dev/null; then
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
				echo "Skipping start image extraction for segment $seg_index (scenestart=$scenestart scene_seg_pos=$scene_seg_pos force_start=$FORCE_START)"
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
	scene_seg_pos=0
	for d in "$INTERMEDIATE_INPUT_FOLDER"/segdata/segment_*; do
		if [ ! -d "$d" ]; then
			# no segments found (glob didn't match)
			break
		fi
		seg_iter=$((seg_iter+1))
		base="$(basename "$d")"
		seg_index=${base#segment_}
		# Determine scenestart flag for this segment (default 1).
		# Decide whether to run i2i according to FORCE_START cadence (per scene).
		scenestart=1
		if [ -n "$segments_scenestart_vals" ]; then
			# seg_index may be zero-padded; compute 1-based field index safely (base-10)
			next_index=$((10#$seg_index + 1))
			scenestart=$(echo "$segments_scenestart_vals" | cut -d',' -f$next_index | tr -d '[:space:]')
			scenestart=${scenestart:-1}
		fi
		if [ "${scenestart:-1}" -eq 1 ] 2>/dev/null ; then
			scene_seg_pos=1
		else
			scene_seg_pos=$((scene_seg_pos + 1))
		fi
		do_i2i=0
		if [ "${FORCE_START:-0}" -le 0 ] 2>/dev/null ; then
			if [ "${scenestart:-0}" -eq 1 ] 2>/dev/null ; then
				do_i2i=1
			fi
		elif [ "${FORCE_START:-0}" -eq 1 ] 2>/dev/null ; then
			do_i2i=1
		else
			_mod=$(((scene_seg_pos - 1) % FORCE_START))
			if [ "${_mod:-1}" -eq 0 ] 2>/dev/null ; then
				do_i2i=1
			fi
		fi
		if [ "${do_i2i:-0}" -ne 1 ] 2>/dev/null ; then
			echo "Skipping i2i for segment $seg_index (scenestart=$scenestart scene_seg_pos=$scene_seg_pos force_start=$FORCE_START)"
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
			# If ComfyUI is down, wait for it before submitting.
			if ! comfyui_is_present; then
				if ! wait_for_comfyui_present "${timeout:-300}" 2; then
					retry_once_or_error "ComfyUI not present; unable to submit i2i request"
				fi
			fi
			submit_i2i() {
				"$PYTHON_BIN_PATH"python.exe $SCRIPTPATH1 "$i2i_api" "$INPUT" "$INTERMEDIATE_OUTPUT_FOLDER/converted" "$lorastrength" "$prompt"
			}
			submit_i2i

			start=`date +%s`
			end=`date +%s`
			secs=0
			queuecount=""
			TASK_ACTIVE_KIND=i2i
			TASK_ACTIVE_T0=$start
			TASK_ACTIVE_T0_SECS=${SECONDS:-}
			TASK_ACTIVE_FRAMES=${seg_cnt:-${I2I_REF_FRAMES:-48}}
			until [ "$queuecount" = "0" ]
			do
				sleep 1
				
				status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
				if [ "$status" = "closed" ]; then
					echo -e $"\e[93mWarning:\e[0m ComfyUI not present. Waiting and retrying current i2i request..."
					if ! wait_for_comfyui_present "${timeout:-300}" 2; then
						TASK_ACTIVE_KIND=
						TASK_ACTIVE_T0=
						TASK_ACTIVE_T0_SECS=
						TASK_ACTIVE_FRAMES=
						retry_once_or_error "ComfyUI did not come back in time (i2i)"
					fi
					[ ${loglevel:-0} -ge 1 ] && echo "Info: re-submitting i2i workflow after ComfyUI restart"
					submit_i2i
					start=`date +%s`
					end=`date +%s`
					secs=0
					queuecount=""
					TASK_ACTIVE_T0=$start
					TASK_ACTIVE_T0_SECS=${SECONDS:-}
					continue
				fi
				if ! curl -sf "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json; then
					echo -e $"\e[93mWarning:\e[0m Failed to query ComfyUI queue. Waiting and retrying current i2i request..."
					if ! wait_for_comfyui_present "${timeout:-300}" 2; then
						TASK_ACTIVE_KIND=
						TASK_ACTIVE_T0=
						TASK_ACTIVE_T0_SECS=
						TASK_ACTIVE_FRAMES=
						retry_once_or_error "ComfyUI did not come back in time (i2i queue query)"
					fi
					[ ${loglevel:-0} -ge 1 ] && echo "Info: re-submitting i2i workflow after ComfyUI queue query failure"
					submit_i2i
					start=`date +%s`
					end=`date +%s`
					secs=0
					queuecount=""
					TASK_ACTIVE_T0=$start
					TASK_ACTIVE_T0_SECS=${SECONDS:-}
					continue
				fi
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
					    TASK_ACTIVE_T0_SECS=
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
			TASK_ACTIVE_T0_SECS=
			TASK_ACTIVE_FRAMES=

			EXTENSION=".png"
			# find most recent converted_*_${EXTENSION} (ComfyUI writes converted_00002_.png etc.)
			INTERMEDIATE=$(wait_for_converted "$INTERMEDIATE_OUTPUT_FOLDER" "$EXTENSION" 20 1) || true

			if [ -e "$INTERMEDIATE" ] && [ -s "$INTERMEDIATE" ] ; then
				if move_with_retry "$INTERMEDIATE" "$target_img" 120 1; then
					echo -e $"\e[92mstep done.\e[0m"
				else
					retry_once_or_error "Step failed (i2i). Unable to move output (file locked?): $INTERMEDIATE"
				fi
			else
				retry_once_or_error "Step failed (i2i). Output missing or zero-length: $INTERMEDIATE"
			fi
		done
	done

	echo "=== STEP 4: generate video segments based transformed images according to work plan using configured IV2V workflow."
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
	# Upper bound estimate: one main chunk per segment.
	# Note: transition chunks are currently disabled (trans_frames is always 0 in this script),
	# but the structure is kept so it can be re-enabled later without refactoring.
	CHUNK_TOTAL_MAX=$((SEG_TOTAL_IV2V * 2))
	seg_iter_iv2v=0

	# Track which chunk belongs to which segment/scenestart/kind for STEP 5 boundary blending.
	# In the current implementation, there is exactly one "main" chunk per workplan segment.
	chunk_meta="$INTERMEDIATE_INPUT_FOLDER/chunk_meta.csv"
	rm -f -- "$chunk_meta" 2>/dev/null || true
	
	# chunk_index: global counter for produced video chunks.
	# Today: 1 chunk per segment (transition chunks disabled). If transitions are re-enabled,
	# there may be additional chunks between segments.
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
		# Currently this check is informational only because transition chunks are disabled
		# (trans_frames remains 0). Scene boundaries are defined by the workplan's scenestart[] flags.
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

		# Generate the main chunk for this workplan segment (one main chunk per segment).
		if [ "$num_frames" -ge 1 ] 2>/dev/null ; then
			idx_p=$(printf "%04d" "$chunk_index")
			chunk_file="$INTERMEDIATE_INPUT_FOLDER/chunk_${idx_p}.mp4"
			# Record metadata even when resuming (chunk already exists)
			echo "chunk_${idx_p}.mp4,${seg_index},${scenestart_iv2v},main" >> "$chunk_meta"
			if [ -e "$chunk_file" ]; then
				echo "Skipping generation; chunk already exists: $chunk_file"
				# Resume/skip should still count as done for plan-based progress/ETA
				task_mark_iv2v_done_no_runtime "$num_frames"
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
				# if [ "${scenestart_iv2v:-1}" -ne 1 ] 2>/dev/null ; then
				# 	prev_seg_index=$((10#$seg_index - 1))
				# 	if [ "$prev_seg_index" -ge 0 ] 2>/dev/null ; then
				# 		prev_seg_p=$(printf "%04d" "$prev_seg_index")
				# 		prev_last_img="$INTERMEDIATE_INPUT_FOLDER/last_${prev_seg_p}.png"
				# 		if [ -s "$prev_last_img" ]; then
				# 			color_image="$prev_last_img"
				# 		fi
				# 	fi
				# fi
				img2="$color_image"

				# generate chunk via iv2v helper using start_frame/num_frames computed from workplan
				iv2v_generate "$img1" "$img2" "$chunk_file" "$num_frames" "$start_frame" 1
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

		# (Disabled) Optional transition chunk between segments (scene boundary helper).
		# Transition chunks are currently not generated because trans_frames is always 0.
		if [ "$trans_frames" -ge 1 ] 2>/dev/null ; then
			idx_p=$(printf "%04d" "$chunk_index")
			chunk_file="$INTERMEDIATE_INPUT_FOLDER/chunk_${idx_p}.mp4"
			# Transition chunks are scene boundaries by definition (do not blend)
			echo "chunk_${idx_p}.mp4,${seg_index},1,transition" >> "$chunk_meta"
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
				# Transition chunk: do not count into plan-based iv2v done frames
				iv2v_generate "$img1" "$control_chunk" "$chunk_file" "$trans_frames" "$start_frame" 0
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
	suffix="$(task_progress_suffix)"
	[ -n "$suffix" ] && echo "$suffix"

	# If FORCE_START=1, blend boundary frames between adjacent main chunks within the same scene
	# (as defined by the workplan: next chunk has scenestart==0) to reduce hard cuts
	# without changing total frames.
	if [ "${FORCE_START:-0}" -eq 1 ] 2>/dev/null && [ -f "$chunk_meta" ]; then
		prev_file=""
		prev_kind=""
		while IFS=',' read -r meta_file meta_seg meta_scene meta_kind; do
			[ -n "${meta_file:-}" ] || continue
			# Only consider boundaries main->main where the *next* chunk is not a scene start
			# (workplan scenestart flag).
			if [ -n "$prev_file" ] && [ "$prev_kind" = "main" ] && [ "${meta_kind:-}" = "main" ] \
				&& is_int "${meta_scene:-}" && [ "${meta_scene:-0}" -eq 0 ] 2>/dev/null; then
				prev_chunk="$INTERMEDIATE_INPUT_FOLDER/$prev_file"
				next_chunk="$INTERMEDIATE_INPUT_FOLDER/$meta_file"
				if [ -s "$prev_chunk" ] && [ -s "$next_chunk" ]; then
					[ ${loglevel:-0} -ge 1 ] && echo "Info: blending inner boundary $prev_file -> $meta_file (FORCED_INNER_SEG_BLEND=${FORCED_INNER_SEG_BLEND})"
					nc_t0=$(date +%s)
					if ! blend_inner_chunk_boundary_if_needed "$prev_chunk" "$next_chunk" "$FORCED_INNER_SEG_BLEND" "${SCENE_WORKFLOW_FPS:-16}"; then
						[ ${loglevel:-0} -ge 1 ] && echo "Warning: inner boundary blending failed for $prev_file -> $meta_file"
					fi
					nc_t1=$(date +%s)
					task_record_noncomfy_runtime $((nc_t1 - nc_t0))
				fi
			fi
			prev_file="$meta_file"
			prev_kind="${meta_kind:-}"
		done < "$chunk_meta"
	fi

	# Build concat list from chunk_*.mp4 in numeric order (chunk_0000, chunk_0001, ...)
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
	# If we know the planned chunk count, enforce it. Otherwise missing chunks can
	# silently truncate the final concat result.
	expected_chunks=${WP_CHUNKS_PLANNED:-0}
	if is_int "${expected_chunks:-}" && [ "${expected_chunks:-0}" -gt 0 ] 2>/dev/null; then
		if [ "${i:-0}" -ne "${expected_chunks:-0}" ] 2>/dev/null; then
			echo -e $"\e[91mError:\e[0m Chunk count mismatch. Found ${i} contiguous chunks (0..$((i-1))) but workplan planned ${expected_chunks}." >&2
			echo "Info: This would truncate the concat result. Check STEP 4 generation/resume state." >&2
			mkdir -p input/vr/tasks/$TASKNAME/error
			mv -- "$ORIGINALINPUT" input/vr/tasks/$TASKNAME/error
			exit 0
		fi
	fi

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
	nc_t0=$(date +%s)
	"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -y -f concat -safe 0 -i "$concat_list" -c copy "$concat_video"
	nc_t1=$(date +%s)
	task_record_noncomfy_runtime $((nc_t1 - nc_t0))
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
	# Duration sanity (best-effort). Important: without padding, -shortest can cut
	# the final output to the (potentially shorter) audio length.
	if [ "${loglevel:-0}" -ge 1 ] 2>/dev/null; then
		concat_dur=$("$FFMPEGPATHPREFIX"ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$concat_video" 2>/dev/null | head -n1)
		src_v_dur=$("$FFMPEGPATHPREFIX"ffprobe -v error -select_streams v:0 -show_entries stream=duration -of default=nw=1:nk=1 "$ORIGINALINPUT" 2>/dev/null | head -n1)
		src_a_dur=$("$FFMPEGPATHPREFIX"ffprobe -v error -select_streams a:0 -show_entries stream=duration -of default=nw=1:nk=1 "$ORIGINALINPUT" 2>/dev/null | head -n1)
		echo "Info: durations (s): concat_video=${concat_dur:-?} source_video=${src_v_dur:-?} source_audio=${src_a_dur:-?}"
		if [ -n "${concat_dur:-}" ] && [ -n "${src_a_dur:-}" ]; then
			# warn if audio is shorter than video by more than ~0.2s
			is_short=$(awk -v v="$concat_dur" -v a="$src_a_dur" 'BEGIN{re="^[0-9]+(\\.[0-9]+)?$"; if(v!~re||a!~re){print 0; exit} if((v-a)>0.2) print 1; else print 0}')
			if [ "${is_short:-0}" -eq 1 ] 2>/dev/null; then
				echo "Warning: source audio is shorter than concat video; mux must pad audio to avoid truncation."
			fi
		fi
	fi

	echo "--- adding audio to $concat_video"

	if [ -n "$audio_stream_index" ]; then
		# Map video from concat and the first audio stream of the original; re-encode audio to AAC
		nc_t0=$(date +%s)
		# IMPORTANT: pad audio with silence so -shortest stops at the video end, not
		# at the (potentially shorter) audio end.
		"$FFMPEGPATHPREFIX"ffmpeg.exe -hide_banner -y -i "$concat_video" -i "$ORIGINALINPUT" -map 0:v:0 -map 1:a:0 -c:v copy -c:a aac -b:a 192k -af apad -shortest "$FINALVIDEO"
		nc_t1=$(date +%s)
		task_record_noncomfy_runtime $((nc_t1 - nc_t0))
		if [ $? -ne 0 ]; then
			echo -e $"\e[91mError:\e[0m Failed muxing audio into final video"
			mkdir -p input/vr/tasks/$TASKNAME/error
			mv -- "$ORIGINALINPUT" input/vr/tasks/$TASKNAME/error
			exit 0
		fi
		if [ "${loglevel:-0}" -ge 1 ] 2>/dev/null; then
			final_dur=$("$FFMPEGPATHPREFIX"ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$FINALVIDEO" 2>/dev/null | head -n1)
			echo "Info: final duration (s): ${final_dur:-?}"
			if [ -n "${final_dur:-}" ] && [ -n "${concat_dur:-}" ]; then
				# warn if final is still shorter than concat by >0.2s
				still_short=$(awk -v v="$concat_dur" -v f="$final_dur" 'BEGIN{if(v==""||f==""){print 0; exit} if((v-f)>0.2) print 1; else print 0}')
				if [ "${still_short:-0}" -eq 1 ] 2>/dev/null; then
					echo "Warning: final video is still shorter than concat_video (unexpected)."
				fi
			fi
		fi
	else
		# No audio: move or copy concat_video to final location
		echo "No audio stream found in source video."
		mkdir -p "$FINALTARGETFOLDER"
		mv -vf -- "$concat_video" "$FINALVIDEO"
	fi

	# Hard validation before finalization/cleanup: if FINALVIDEO is shorter than
	# concat_video by more than a small tolerance, abort with exit!=0 so the
	# intermediate folder is kept for debugging/resume.
	# (This catches regressions like mux truncation and prevents silent 13s->10s.)
	STEP5_DUR_TOL_S=${STEP5_DUR_TOL_S:-0.2}
	if [ ! -s "$FINALVIDEO" ]; then
		echo -e $"\e[91mError:\e[0m Step 5 produced no final video (missing or zero-length): $FINALVIDEO" >&2
		echo "Info: keeping intermediate folder for inspection: $INTERMEDIATE_INPUT_FOLDER" >&2
		exit 1
	fi
	# Use container duration (format.duration) because stream durations may be N/A.
	concat_dur_chk=$("$FFMPEGPATHPREFIX"ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$concat_video" 2>/dev/null | head -n1)
	final_dur_chk=$("$FFMPEGPATHPREFIX"ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$FINALVIDEO" 2>/dev/null | head -n1)
	if [ -n "${concat_dur_chk:-}" ] && [ -n "${final_dur_chk:-}" ]; then
		final_short=$(awk -v v="$concat_dur_chk" -v f="$final_dur_chk" -v t="$STEP5_DUR_TOL_S" 'BEGIN{re="^[0-9]+(\\.[0-9]+)?$"; if(v!~re||f!~re||t!~re){print -1; exit} if((v-f)>t) print 1; else print 0}')
		if [ "${final_short:-0}" -eq -1 ] 2>/dev/null; then
			[ "${loglevel:-0}" -ge 1 ] 2>/dev/null && echo "Warning: Step 5 duration probe not numeric (concat='${concat_dur_chk}' final='${final_dur_chk}' tol='${STEP5_DUR_TOL_S}'); skipping strict validation."
		elif [ "${final_short:-0}" -eq 1 ] 2>/dev/null; then
			echo -e $"\e[91mError:\e[0m Final video shorter than concat_video by more than ${STEP5_DUR_TOL_S}s." >&2
			echo "Info: durations (s): concat_video=${concat_dur_chk} final=${final_dur_chk}" >&2
			echo "Info: keeping intermediate folder for inspection: $INTERMEDIATE_INPUT_FOLDER" >&2
			exit 1
		fi
		[ "${loglevel:-0}" -ge 1 ] 2>/dev/null && echo "Info: final duration OK (s): concat_video=${concat_dur_chk} final=${final_dur_chk} tol=${STEP5_DUR_TOL_S}"
	else
		[ "${loglevel:-0}" -ge 1 ] 2>/dev/null && echo "Warning: could not probe durations for Step 5 validation (concat='${concat_dur_chk:-}' final='${final_dur_chk:-}')."
	fi

	mkdir -p input/vr/tasks/$TASKNAME/done
	mv -- $ORIGINALINPUT input/vr/tasks/$TASKNAME/done
	rm -rf -- $INTERMEDIATE_INPUT_FOLDER
	rm -rf -- $INTERMEDIATE_OUTPUT_FOLDER
	task_log_estimator_recommendations
	echo -e $"\e[92mSuccess:\e[0m Final video written -> $FINALVIDEO"
fi
exit 0

