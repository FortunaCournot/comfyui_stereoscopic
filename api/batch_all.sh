#!/bin/sh
# Executes the whole SBS workbench pipeline
# Copyright (c) 2025 Fortuna Cournot. MIT License.

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).
# Prerequisite: Placed sbs_api.py somewhere and configured path variables below.


# abolute path of ComfyUI folder in your ComfyUI_windows_portable
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`

cd $COMFYUIPATH

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

export CONFIGFILE
if [ -e $CONFIGFILE ] ; then
	loglevel=$(awk -F "=" '/loglevel=/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
	[ $loglevel -ge 2 ] && set -x
    config_version=$(awk -F "=" '/config_version=/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
	PIPELINE_AUTOFORWARD=$(awk -F "=" '/PIPELINE_AUTOFORWARD=/ {print $2}' $CONFIGFILE) ; PIPELINE_AUTOFORWARD=${PIPELINE_AUTOFORWARD:-1}
	COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST=/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
	COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT=/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
	export COMFYUIHOST COMFYUIPORT
	# Source filesystem helpers (baseline counting functions)
	if [ -z "$COMFYUIPATH" ]; then
		echo "Error: COMFYUIPATH not set in $(basename \"$0\") (cwd=$(pwd)). Start script from repository root."; exit 1;
	fi
	LIB_FS="$COMFYUIPATH/custom_nodes/comfyui_stereoscopic/api/lib_fs.sh"
	if [ -f "$LIB_FS" ]; then
		. "$LIB_FS" || { echo "Error: failed to source canonical $LIB_FS in $(basename \"$0\") (cwd=$(pwd))"; exit 1; }
	else
		echo "Error: required lib_fs not found at canonical path: $LIB_FS"; exit 1;
	fi
	# Refresh FS status once for this run so property-based counts are not stale
	if [ -n "${PYTHON:-}" ] && [ -x "${PYTHON:-}" ]; then
		"$PYTHON" ./custom_nodes/comfyui_stereoscopic/api/compute_fs_status.py >/dev/null 2>&1 || true
	fi
else
    touch "$CONFIGFILE"
fi

onExit() {
	exit_code=$?
	[ $loglevel -ge 1 ] && echo "Exit code: $exit_code"
	exit $exit_code
}
trap onExit EXIT

FREESPACE=$(df -khBG . | tail -n1 | awk '{print $4}')

# Path to unused flags (list of disabled items)
UNUSED_PROPS=./user/default/comfyui_stereoscopic/unused.properties

# Check if a given stage/task/customtask name is listed as unused (disabled).
# Returns 0 if disabled, 1 otherwise.
is_disabled() {
	local name="$1"
	local key
	if [[ "$name" =~ ^tasks/_ ]]; then
		key=customtask
	elif [[ "$name" =~ ^tasks/ ]]; then
		key=task
	else
		key=stage
	fi
	if [ ! -f "$UNUSED_PROPS" ]; then
		return 1
	fi
	local vals
	vals=$(awk -F"=" -v k="$key" '$1==k {print $2; exit}' "$UNUSED_PROPS" | tr -d '\r')
	if [ -z "$vals" ]; then
		return 1
	fi
	IFS=',' read -ra arr <<< "$vals"
	for v in "${arr[@]}"; do
		v=$(echo "$v" | sed -e 's/^\s*//' -e 's/\s*$//')
		if [ "$v" = "$name" ]; then
			return 0
		fi
	done
	return 1
}

FREESPACE=${FREESPACE%G}
MINSPACE=10
status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
if test $# -ne 0
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 "
    echo "E.g.: $0 "
elif [ "$status" = "closed" ]; then
	echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on port 8188"
elif [[ $FREESPACE -lt $MINSPACE ]] ; then
	echo -e $"\e[91mError:\e[0m Less than $MINSPACE""G left on device: $FREESPACE""G"
	./custom_nodes/comfyui_stereoscopic/api/clear.sh || exit 1
	FREESPACE=$(df -khBG . | tail -n1 | awk '{print $4}')
	FREESPACE=${FREESPACE%G}
	if [[ $FREESPACE -lt $MINSPACE ]] ; then
		exit 1
	fi
elif [ -d "custom_nodes" ]; then

	### CHECK FOR OPTIONAL NODE PACKAGES ###
	DUBBING_DEP_ERROR=
	if [ ! -d custom_nodes/comfyui-florence2 ]; then
		echo -e $"\e[91mError:\e[0m Custom nodes ComfyUI-Florence2 could not be found."
		DUBBING_DEP_ERROR="x"
	fi
	if [ ! -d custom_nodes/comfyui-mmaudio ] ; then
		echo -e $"\e[91mError:\e[0m Custom nodes ComfyUI-MMAudio could not be found."
		DUBBING_DEP_ERROR="x"
	fi
	
	# LOCAL: prepare move output to next stage input (This should happen in daemon, too)
	mkdir -p input/vr/scaling input/vr/fullsbs

	# workaround for recovery problem.
	#./custom_nodes/comfyui_stereoscopic/api/clear.sh || exit 1

	[ -e user/default/comfyui_stereoscopic/.pipelinepause ] && exit 0
	CAPCOUNT=$(count_files_with_exts "input/vr/caption" mp4 webm png jpg jpeg webp)
	# zero if caption stage disabled
	if [ ${CAPCOUNT:-0} -gt 0 ] && is_disabled "caption"; then CAPCOUNT=0; echo "skipped caption stage"; fi
	if [ $CAPCOUNT -gt 0 ] ; then
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "******** CAPTION *********"
		[ $loglevel -ge 1 ] && echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_caption.sh || exit 1
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh caption || exit 1 )
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
	fi

	[ -e user/default/comfyui_stereoscopic/.pipelinepause ] && exit 0
	SCALECOUNT=$(count_files_with_exts "input/vr/scaling" mp4 png jpg jpeg webm webp)
	OVERRIDECOUNT=$(count_files_with_exts "input/vr/scaling/override" mp4 png jpg jpeg webm webp)
	# zero if scaling stage disabled
	if { [ ${SCALECOUNT:-0} -gt 0 ] || [ ${OVERRIDECOUNT:-0} -gt 0 ]; } && is_disabled "scaling"; then SCALECOUNT=0; OVERRIDECOUNT=0; echo "skipped scaling stage"; fi
	if [ $SCALECOUNT -ge 1 ] || [ $OVERRIDECOUNT -ge 1 ]; then
		MEMFREE=`awk '/MemFree/ { printf "%.0f \n", $2/1024/1024 }' /proc/meminfo`
		MEMTOTAL=`awk '/MemTotal/ { printf "%.0f \n", $2/1024/1024 }' /proc/meminfo`
		if [ $MEMFREE -ge 16 ] ; then
			# UPSCALING: Video -> Video. Limited to 60s and 4K.
			# In:  input/vr/scaling
			# Out: output/vr/scaling
			[ $loglevel -ge 1 ] && echo "**************************"
			[ $loglevel -ge 0 ] && echo "******** SCALING *********"
			[ $loglevel -ge 1 ] && echo "**************************"
			if [ $SCALECOUNT -ge 1 ]; then
				./custom_nodes/comfyui_stereoscopic/api/batch_scaling.sh || exit 1
			fi
			if [ $OVERRIDECOUNT -ge 1 ]; then
				./custom_nodes/comfyui_stereoscopic/api/batch_scaling.sh /override || exit 1
			fi
			rm -f user/default/comfyui_stereoscopic/.daemonstatus
		else
			echo -e $"\e[93mWarning:\e[0m Less than 16GB of free memory - Skipped scaling. Memory: $MEMFREE/ $MEMTOTAL"
			mv -- input/vr/scaling/*.* output/vr/scaling
		fi
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh scaling || exit 1 )
	fi


	[ -e user/default/comfyui_stereoscopic/.pipelinepause ] && exit 0
	SLIDECOUNT=$(count_files_with_exts "input/vr/slides" png jpg jpeg webm webp)
	# zero if slides stage disabled
	if [ ${SLIDECOUNT:-0} -gt 0 ] && is_disabled "slides"; then SLIDECOUNT=0; echo "skipped slides stage"; fi
	if [ $SLIDECOUNT -ge 2 ]; then
		# PREPARE 4K SLIDES
		# In:  input/vr/slides
		# Out: output/slides
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "***** PREPARE SLIDES *****"
		[ $loglevel -ge 1 ] && echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_prepare_slides.sh || exit 1
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh slides || exit 1 )
	fi
	
	
	
	[ -e user/default/comfyui_stereoscopic/.pipelinepause ] && exit 0
	SBSCOUNT=$(count_files_with_exts "input/vr/fullsbs" mp4 png jpg jpeg webm webp)
	# zero if fullsbs stage disabled
	if [ ${SBSCOUNT:-0} -gt 0 ] && is_disabled "fullsbs"; then SBSCOUNT=0; echo "skipped fullsbs stage"; fi
	if [ $SBSCOUNT -ge 1 ]; then
		# SBS CONVERTER: Video -> Video, Image -> Image
		# In:  input/vr/fullsbs
		# Out: output/sbs
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "*****  SBSCONVERTING *****"
		[ $loglevel -ge 1 ] && echo "**************************"
		SBS_DEPTH_SCALE=$(awk -F "=" '/SBS_DEPTH_SCALE=/ {print $2}' $CONFIGFILE) ; SBS_DEPTH_SCALE=${SBS_DEPTH_SCALE:-"1.25"}
		SBS_DEPTH_OFFSET=$(awk -F "=" '/SBS_DEPTH_OFFSET=/ {print $2}' $CONFIGFILE) ; SBS_DEPTH_OFFSET=${SBS_DEPTH_OFFSET:-"0.0"}
		./custom_nodes/comfyui_stereoscopic/api/batch_sbsconverter.sh $SBS_DEPTH_SCALE $SBS_DEPTH_OFFSET
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh fullsbs || exit 1 )
	fi

	[ -e user/default/comfyui_stereoscopic/.pipelinepause ] && exit 0
	INTERPOLATECOUNT=$(count_files_with_exts "input/vr/interpolate" mp4 webm)
	# zero if interpolate stage disabled
	if [ ${INTERPOLATECOUNT:-0} -gt 0 ] && is_disabled "interpolate"; then INTERPOLATECOUNT=0; echo "skipped interpolate stage"; fi
	if [ $INTERPOLATECOUNT -gt 0 ] ; then
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "****** INTERPOLATE *******"
		[ $loglevel -ge 1 ] && echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_interpolate.sh || exit 1
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh interpolate || exit 1 )
	fi


	[ -e user/default/comfyui_stereoscopic/.pipelinepause ] && exit 0
	SINGLELOOPCOUNT=$(count_files_with_exts "input/vr/singleloop" mp4 webm)
	# zero if singleloop stage disabled
	if [ ${SINGLELOOPCOUNT:-0} -gt 0 ] && is_disabled "singleloop"; then SINGLELOOPCOUNT=0; echo "skipped singleloop stage"; fi
	if [ $SINGLELOOPCOUNT -ge 1 ]; then
		# SINGLE LOOP
		# In:  input/vr/singleloop_in
		# Out: output/vr/singleloop
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "****** SINGLE LOOP *******"
		[ $loglevel -ge 1 ] && echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_singleloop.sh || exit 1
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh singleloop || exit 1 )
	fi

	
	[ -e user/default/comfyui_stereoscopic/.pipelinepause ] && exit 0
	SLIDESBSCOUNT=$(count_files_with_exts "input/vr/slideshow" png)
	# zero if slideshow stage disabled
	if [ ${SLIDESBSCOUNT:-0} -gt 0 ] && is_disabled "slideshow"; then SLIDESBSCOUNT=0; echo "skipped slideshow stage"; fi
	if [ $SLIDESBSCOUNT -ge 2 ]; then
		# MAKE SLIDESHOW
		# In:  input/vr/slideshow
		# Out: output/vr/slideshow
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "***** MAKE SLIDESHOW *****"
		[ $loglevel -ge 1 ] && echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_make_slideshow.sh || exit 1
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh slideshow || exit 1 )
	fi


	[ -e user/default/comfyui_stereoscopic/.pipelinepause ] && exit 0
	CONCATCOUNT=$(count_files_with_exts "input/vr/concat" mp4)
	OVERRIDECOUNT=$(count_files_with_exts "input/vr/concat/ignorename" mp4)
	# zero if concat stage disabled
	if { [ ${CONCATCOUNT:-0} -gt 0 ] || [ ${OVERRIDECOUNT:-0} -gt 0 ]; } && is_disabled "concat"; then CONCATCOUNT=0; OVERRIDECOUNT=0; echo "skipped concat stage"; fi
	if [ $CONCATCOUNT -ge 1 ] || [ $OVERRIDECOUNT -ge 1 ]; then
		# CONCAT
		# In:  input/vr/concat_in
		# Out: output/vr/concat
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "******** CONCAT **********"
		[ $loglevel -ge 1 ] && echo "**************************"
		echo -ne $"\e[97m\e[1m=== CONCAT READY - PRESS RETURN TO START ===\e[0m" ; read forgetme ; echo "starting..."

		if [ $CONCATCOUNT -ge 1 ]; then
			./custom_nodes/comfyui_stereoscopic/api/batch_concat.sh || exit 1
		fi
		if [ $OVERRIDECOUNT -ge 1 ]; then
			./custom_nodes/comfyui_stereoscopic/api/batch_concat.sh /ignorename || exit 1
		fi
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh concat || exit 1 )
	fi

	### SKIP IF DEPENDENCY CHECK FAILED ###
	[ -e user/default/comfyui_stereoscopic/.pipelinepause ] && exit 0
	DUBCOUNTSFX=$(count_files_with_exts "input/vr/dubbing/sfx" mp4 webm)
	# zero if dubbing/sfx disabled
	if [ ${DUBCOUNTSFX:-0} -gt 0 ] && is_disabled "dubbing/sfx"; then DUBCOUNTSFX=0; echo "skipped dubbing/sfx stage"; fi
	if [[ -z $DUBBING_DEP_ERROR ]] && [ $DUBCOUNTSFX -gt 0 ]; then
		if [ -x "$(command -v nvidia-smi)" ]; then
			# DUBBING: Video -> Video with SFX
			# In:  input/vr/dubbing/sfx
			# Out: output/vr/dubbing/sfx
			[ $loglevel -ge 1 ] && echo "**************************"
			[ $loglevel -ge 0 ] && echo "****** DUBBING SFX *******"
			[ $loglevel -ge 1 ] && echo "**************************"
			./custom_nodes/comfyui_stereoscopic/api/batch_dubbing_sfx.sh || exit 1
			rm -f user/default/comfyui_stereoscopic/.daemonstatus
			[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh dubbing/sfx || exit 1 )
		else
			echo 'Warning: nvidea-smi is not installed. Dubbing required CUDA.'
		fi

	elif [ $DUBCOUNTSFX -gt 0 ]; then
		mkdir -p input/vr/dubbing/sfx/error
		mv -fv input/vr/dubbing/sfx/*.mp4 input/vr/dubbing/sfx/error
	fi

	### SKIP IF DEPENDENCY CHECK FAILED ###
	[ -e user/default/comfyui_stereoscopic/.pipelinepause ] && exit 0
	DUBCOUNTMUSIC=$(count_files_with_exts "input/vr/dubbing/music" mp4 webm)
	# zero if dubbing/music disabled
	if [ ${DUBCOUNTMUSIC:-0} -gt 0 ] && is_disabled "dubbing/music"; then DUBCOUNTMUSIC=0; echo "skipped dubbing/music stage"; fi
	if [[ -z $DUBBING_DEP_ERROR ]] && [ $DUBCOUNTMUSIC -gt 0 ]; then
		if [ -x "$(command -v nvidia-smi)" ]; then
			# DUBBING: Video -> Video with music
			# In:  input/vr/dubbing/music
			# Out: output/vr/dubbing/music
			[ $loglevel -ge 1 ] && echo "**************************"
			[ $loglevel -ge 0 ] && echo "***** DUBBING MUSIC ******"
			[ $loglevel -ge 1 ] && echo "**************************"
			./custom_nodes/comfyui_stereoscopic/api/batch_dubbing_music.sh || exit 1
			rm -f user/default/comfyui_stereoscopic/.daemonstatus
			[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh dubbing/music || exit 1 )
		else
			echo 'Warning: nvidea-smi is not installed. Dubbing required CUDA.'
		fi

	elif [ $DUBCOUNTMUSIC -gt 0 ]; then
		mkdir -p input/vr/dubbing/music/error
		mv -fv input/vr/dubbing/music/*.mp4 input/vr/dubbing/music/error
	fi

	### SKIP IF CONFIG CHECK FAILED ###
	[ -e user/default/comfyui_stereoscopic/.pipelinepause ] && exit 0
	WMECOUNT=$(count_files_with_exts "input/vr/watermark/encrypt" png jpg jpeg)
	WMDCOUNT=$(count_files_with_exts "input/vr/watermark/decrypt" png jpg jpeg)
	# zero if watermark stages disabled
	if [ ${WMECOUNT:-0} -gt 0 ] && is_disabled "watermark/encrypt"; then WMECOUNT=0; echo "skipped watermark/encrypt stage"; fi
	if [ ${WMDCOUNT:-0} -gt 0 ] && is_disabled "watermark/decrypt"; then WMDCOUNT=0; fi
	if [ $WMECOUNT -gt 0 ] ; then
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "****** ENCRYPTING ********"
		[ $loglevel -ge 1 ] && echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_watermark_encrypt.sh || exit 1
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh watermark/encrypt || exit 1 )
	fi
	if [ $WMDCOUNT -gt 0 ] ; then
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "****** DECRYPTING ********"
		[ $loglevel -ge 1 ] && echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_watermark_decrypt.sh || exit 1
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
	fi

	[ -e user/default/comfyui_stereoscopic/.pipelinepause ] && exit 0
	# TASKCOUNT: sum files in each task directory (non-recursive)
	TASKCOUNT=$(compute_task_count)
	if [ $TASKCOUNT -gt 0 ] ; then
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "********* TASKS **********"
		[ $loglevel -ge 1 ] && echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_tasks.sh || exit 1
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
		[ -e user/default/comfyui_stereoscopic/.pipelinepause ] && exit 0

		# Build task list (skip '.'), then iterate with progress bar and per-task summary
		TASKDIR_LIST=$(find output/vr/tasks -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
		TOTAL=$(echo "$TASKDIR_LIST" | sed '/^\s*$/d' | wc -l | tr -d '[:space:]')
		if [ -z "$TOTAL" ] || [ "$TOTAL" -eq 0 ] ; then
			TOTAL=0
		fi
		if [ "$TOTAL" -gt 0 ] ; then
			idx=0
			WIDTH=30
			while IFS= read -r taskdir; do
				[ -z "$taskdir" ] && continue
				task=${taskdir#output/vr/tasks/}
				idx=$((idx+1))
				if [ $PIPELINE_AUTOFORWARD -ge 1 ] ; then
					filled=$(( idx * WIDTH / TOTAL ))
					empty=$(( WIDTH - filled ))
					filled_str=$(awk -v n="$filled" 'BEGIN{for(i=0;i<n;i++) printf "#"}')
					empty_str=$(awk -v n="$empty" 'BEGIN{for(i=0;i<n;i++) printf "-"}')
					BAR="[$filled_str$empty_str]"
					SUMMARY=$(SUMMARY_MODE=1 ./custom_nodes/comfyui_stereoscopic/api/forward.sh tasks/$task)
					rc=$?
					if [ $rc -ne 0 ]; then exit $rc; fi
					SUMMARY=$(echo "$SUMMARY" | tr -d '\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
					printf '%s %s %s\n' "$BAR" "$task" "$SUMMARY"
				fi
			done <<EOF
$TASKDIR_LIST
EOF
		fi

	fi
	
	[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh check/judge || exit 1 )


else
	  echo -e $"\e[91mError:\e[0m Wrong path to script. COMFYUIPATH=$COMFYUIPATH"
fi
exit 0

