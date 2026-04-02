#!/bin/sh
# Executes the whole SBS workbench pipeline again and again ...
# Copyright (c) 2025 Fortuna Cournot. MIT License.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../..`

cd $COMFYUIPATH

NOCLEANUP=0
while [ -e user/default/comfyui_stereoscopic/.daemonactive ]; do
    read -p "lock file exists. daemon already active or was killed. Start again? " yn
    case $yn in
        [Yy]* ) break;;
        [Nn]* ) NOCLEANUP=1; exit 0;;
        * ) echo "Please answer yes or no.";;
    esac
done

cleanup() {
	exit_code=$?
	rm -f user/default/comfyui_stereoscopic/.daemonactive
	rm -f user/default/comfyui_stereoscopic/.daemonstatus
	rm -f user/default/comfyui_stereoscopic/.pipelineactive
	rm -f user/default/comfyui_stereoscopic/.forwardactive
	#echo "Exit code $exit_code"
	while [[ ${exit_code} -ne 0 ]]; do
		read -p "Error/Interrupt detected. Please press enter to quit: " yn
		case $yn in
			[A-Za-z]* )
				exit_code=0
				break;;
			* )
				echo "Please answer yes or no to quit (no options)."
				break;;
		esac
	done
    exit 0 # exit script after cleanup
}

trap cleanup EXIT

now_epoch() {
	date +%s
}

log_info() {
	[ "${loglevel:-0}" -ge 0 ] && echo "Info: $*"
}

log_step_start() {
	[ "${loglevel:-0}" -ge 0 ] && echo "Info: $1..."
}

log_step_end() {
	local label="$1"
	local started="$2"
	local finished elapsed
	finished=$(now_epoch)
	elapsed=$((finished-started))
	[ "${loglevel:-0}" -ge 0 ] && echo "Info: $label done (${elapsed}s)."
}

# Verbose wrappers: only show these step logs when loglevel >= 1
log_step_start_verbose() {
	[ "${loglevel:-0}" -ge 1 ] && log_step_start "$@"
}

log_step_end_verbose() {
	[ "${loglevel:-0}" -ge 1 ] && log_step_end "$@"
}

# Verbose wrapper for slow-step logging: only show when loglevel >= 1
log_step_if_slow_verbose() {
	local label="$1"
	local started="$2"
	local threshold="${3:-2}"
	if [ "${loglevel:-0}" -ge 1 ]; then
		log_step_if_slow "$label" "$started" "$threshold"
	fi
}

log_step_if_slow() {
	local label="$1"
	local started="$2"
	local threshold="${3:-2}"
	local finished elapsed
	finished=$(now_epoch)
	elapsed=$((finished-started))
	if [ "${loglevel:-0}" -ge 0 ] && [ "$elapsed" -ge "$threshold" ] ; then
		echo "Info: $label took ${elapsed}s."
	fi
}

IDLE_WAITING_ACTIVE=0
IDLE_WAITING_SUFFIX=

idle_waiting_clear_line() {
	local clear_width="${columns:-120}"
	[ "${loglevel:-0}" -ge 0 ] && printf '\r%*s\r' "$clear_width" ''
}

idle_waiting_show() {
	local suffix="${1:-}"
	IDLE_WAITING_ACTIVE=1
	IDLE_WAITING_SUFFIX="$suffix"
	idle_waiting_clear_line
	[ "${loglevel:-0}" -ge 0 ] && printf '\e[2mWaiting for new files%s\e[0m                     \r' "$IDLE_WAITING_SUFFIX"
}

idle_waiting_append_dot() {
	[ "$IDLE_WAITING_ACTIVE" -eq 1 ] || return 1
	IDLE_WAITING_SUFFIX="${IDLE_WAITING_SUFFIX}."
	idle_waiting_clear_line
	[ "${loglevel:-0}" -ge 0 ] && printf '\e[2mWaiting for new files%s\e[0m                     \r' "$IDLE_WAITING_SUFFIX"
	return 0
}

idle_waiting_append_dot_if_slow() {
	local started="$1"
	local threshold="${2:-2}"
	local finished elapsed
	[ "$IDLE_WAITING_ACTIVE" -eq 1 ] || return 1
	finished=$(now_epoch)
	elapsed=$((finished-started))
	if [ "$elapsed" -ge "$threshold" ] ; then
		idle_waiting_append_dot
		return 0
	fi
	return 1
}

idle_waiting_endline() {
	if [ "$IDLE_WAITING_ACTIVE" -eq 1 ] ; then
		[ "${loglevel:-0}" -ge 0 ] && printf '\n'
		IDLE_WAITING_ACTIVE=0
		IDLE_WAITING_SUFFIX=
	fi
}

compute_task_count_with_spinner() {
	local tmp_file task_pid spinner_frame spinner_visible task_count
	tmp_file=$(mktemp 2>/dev/null || echo "./user/default/comfyui_stereoscopic/.taskcount.$$".tmp)
	compute_task_count >"$tmp_file" 2>/dev/null &
	task_pid=$!
	spinner_frame=0
	spinner_visible=0

	while kill -0 "$task_pid" 2>/dev/null; do
		if [ "${loglevel:-0}" -ge 0 ] && [ -t 1 ] && [ "$spinner_frame" -ge 5 ] ; then
			case $((spinner_frame % 4)) in
				0) spinner_char='|' ;;
				1) spinner_char='/' ;;
				2) spinner_char='-' ;;
				*) spinner_char='\\' ;;
			esac
			spinner_visible=1
			printf '\r\e[2mCounting task files %s\e[0m                     ' "$spinner_char"
		fi
		spinner_frame=$((spinner_frame + 1))
		sleep 0.2
	done

	wait "$task_pid" 2>/dev/null || true
	if [ "$spinner_visible" -eq 1 ] ; then
		idle_waiting_clear_line
	fi

	if [ -f "$tmp_file" ] ; then
		task_count=$(cat "$tmp_file" 2>/dev/null)
		rm -f -- "$tmp_file" 2>/dev/null
		printf '%s\n' "${task_count:-0}"
	else
		printf '0\n'
	fi
}

mkdir -p input/vr/slideshow input/vr/dubbing/sfx input/vr/dubbing/music input/vr/scaling input/vr/fullsbs input/vr/scaling/override input/vr/singleloop input/vr/slides input/vr/concat input/vr/ignorename input/vr/downscale/4K input/vr/caption input/vr/check/rate input/vr/check/released
mkdir -p output/vr/check/rate output/vr/check/released

env_started=$(now_epoch)
log_step_start "Loading daemon environment"
source ./user/default/comfyui_stereoscopic/.environment
log_step_end "Loading daemon environment" "$env_started"

prereq_started=$(now_epoch)
log_step_start "Checking daemon prerequisites"
./custom_nodes/comfyui_stereoscopic/api/prerequisites.sh || exit 1
log_step_end "Checking daemon prerequisites" "$prereq_started"

# filesystem counting helpers (robust sourcing with diagnostics)
# Prefer the canonical location inside the repo root (COMFYUIPATH).
# Fallback to script-relative locations if necessary.
LIB_FS="$COMFYUIPATH/custom_nodes/comfyui_stereoscopic/api/lib_fs.sh"
if [ -f "$LIB_FS" ]; then
	. "$LIB_FS" || { echo "Error: failed to source canonical $LIB_FS in $(basename \"$0\") (cwd=$(pwd))"; exit 1; }
else
	echo "Error: required lib_fs not found at canonical path: $LIB_FS";
	echo "Please ensure you run the daemon from the repository root (COMFYUIPATH) and that the file exists.";
	exit 1;
fi
if ! command -v count_files_any_ext >/dev/null 2>&1 || ! command -v count_files_with_exts >/dev/null 2>&1 ; then
	echo "Error: lib_fs functions missing after sourcing $LIB_FS in $(basename \"$0\") (cwd=$(pwd))"; exit 1;
fi

# Source forward helper once (avoid re-sourcing inside loop)
. ./custom_nodes/comfyui_stereoscopic/api/lib_forward.sh


# Use Systempath for python by default, but set it explictly for comfyui portable.
PYTHON_BIN_PATH=
if [ -d "../python_embeded" ]; then
  PYTHON_BIN_PATH=../python_embeded/
fi
mkdir -p user/default/comfyui_stereoscopic
rm -f -- user/default/comfyui_stereoscopic/.daemonstatus 2>/dev/null
rm -f -- user/default/comfyui_stereoscopic/.forwardactive 2>/dev/null
touch user/default/comfyui_stereoscopic/.daemonactive
OPENCV_FFMPEG_READ_ATTEMPTS=8192
export OPENCV_FFMPEG_READ_ATTEMPTS
gui_started=$(now_epoch)
log_step_start "Starting daemon GUI helper"
"$PYTHON_BIN_PATH"python.exe ./custom_nodes/comfyui_stereoscopic/gui/python/vrweare.py 2>/dev/null &
log_step_end "Starting daemon GUI helper" "$gui_started"

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

SHORT_CONFIGFILE=$CONFIGFILE
CONFIGFILE=`realpath "$CONFIGFILE"`
export CONFIGFILE

config_started=$(now_epoch)
log_step_start "Loading daemon configuration"
loglevel=$(awk -F "=" '/loglevel=/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
[ $loglevel -ge 2 ] && set -x

config_version=$(awk -F "=" '/config_version=/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
PIPELINE_AUTOFORWARD=$(awk -F "=" '/PIPELINE_AUTOFORWARD=/ {print $2}' $CONFIGFILE) ; PIPELINE_AUTOFORWARD=${PIPELINE_AUTOFORWARD:-1}
# Track previous PIPELINE_AUTOFORWARD to detect 0->1 transitions
PREV_PIPELINE_AUTOFORWARD=$PIPELINE_AUTOFORWARD
FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX=/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}
UPSCALEMODELx4=$(awk -F "=" '/UPSCALEMODELx4=/ {print $2}' $CONFIGFILE) ; UPSCALEMODELx4=${UPSCALEMODELx4:-"RealESRGAN_x4plus.pth"}
UPSCALEMODELx2=$(awk -F "=" '/UPSCALEMODELx2=/ {print $2}' $CONFIGFILE) ; UPSCALEMODELx2=${UPSCALEMODELx2:-"RealESRGAN_x4plus.pth"}
FLORENCE2MODEL=$(awk -F "=" '/FLORENCE2MODEL=/ {print $2}' $CONFIGFILE) ; FLORENCE2MODEL=${FLORENCE2MODEL:-"microsoft/Florence-2-base"}
DEPTH_MODEL_CKPT=$(awk -F "=" '/DEPTH_MODEL_CKPT=/ {print $2}' $CONFIGFILE) ; DEPTH_MODEL_CKPT=${DEPTH_MODEL_CKPT:-"depth_anything_v2_vitl.pth"}

TVAI_BIN_DIR=$(awk -F "=" '/TVAI_BIN_DIR=/ {print $2}' $CONFIGFILE | head -n 1) ; TVAI_BIN_DIR=${TVAI_BIN_DIR:-""}
TVAI_MODEL_DATA_DIR=$(awk -F "=" '/TVAI_MODEL_DATA_DIR=/ {print $2}' $CONFIGFILE) ; TVAI_MODEL_DATA_DIR=${TVAI_MODEL_DATA_DIR:-""}
TVAI_MODEL_DIR=$(awk -F "=" '/TVAI_MODEL_DIR=/ {print $2}' $CONFIGFILE) ; TVAI_MODEL_DIR=${TVAI_MODEL_DIR:-""}
log_step_end "Loading daemon configuration" "$config_started"

CONFIGERROR=

columns=$(tput cols)

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
	# get the comma-separated value for the key robustly
	local vals
	vals=$(awk -F"=" -v k="$key" '$1==k {print $2; exit}' "$UNUSED_PROPS" | tr -d '\r')
	if [ -z "$vals" ]; then
		return 1
	fi
	# split and compare exact matches
	IFS=',' read -ra arr <<< "$vals"
	for v in "${arr[@]}"; do
		v=$(echo "$v" | sed -e 's/^\s*//' -e 's/\s*$//')
		if [ "$v" = "$name" ]; then
			return 0
		fi
	done
	return 1
}

if test $# -ne 0
then
	# targetprefix path is relative; parent directories are created as needed
	echo "Usage: $0 "
	echo "E.g.: $0 "
else
	SERVERERROR=
	
	if [ -e custom_nodes/comfyui_stereoscopic/pyproject.toml ]; then
		VERSION=`cat custom_nodes/comfyui_stereoscopic/pyproject.toml | grep "version = " | grep -v "minversion" | grep -v "target-version"`
	else
		echo -e $"\e[91mError:\e[0m script not started in ComfyUI folder!"
		exit
	fi

	### WAIT FOR OLD QUEUE TO FINISH ###
	queuecheck_started=$(now_epoch)
	log_step_start "Checking existing ComfyUI queue"
	COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST=/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
	COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT=/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
	status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
	if [ ! "$status" = "closed" ]; then
		curl -silent "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json
		queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
		[ $loglevel -ge 0 ] && echo "Info: ComfyUI busy. Queuecount: $queuecount"
		queuecount=
	else
		log_info "ComfyUI queue check skipped because server is not reachable."
	fi
	log_step_end "Checking existing ComfyUI queue" "$queuecheck_started"

	### GET READY ... ###
	echo ""
	[ $loglevel -ge 0 ] && echo -e $"\e[97m\e[1mStereoscopic Pipeline Processing started. $VERSION\e[0m"
	[ $loglevel -ge 0 ] && echo -e $"\e[2m"
	[ $loglevel -ge 0 ] && echo "Waiting for your files to be placed in folders:"

	### CHECK FOR OPTIONAL NODE PACKAGES AND OTHER PROBLEMS ###
	if [ ! -d custom_nodes/comfyui-florence2 ]; then
		[ $loglevel -ge 0 ] && echo -e $"\e[93mWarning:\e[0m Custom nodes ComfyUI-Florence2 could not be found. Use Custom Nodes Manager to install v1.0.5."
		CONFIGERROR="x"
	fi
	if [ ! -d custom_nodes/comfyui-mmaudio ] ; then
		[ $loglevel -ge 0 ] && echo -e $"\e[93mWarning:\e[0m Custom nodes ComfyUI-MMAudio could not be found. Use Custom Nodes Manager to install v1.0.2."
		CONFIGERROR="x"
	fi
	[ $columns -lt 120 ] &&	CONFIGERROR="x"  && echo -e $"\e[93mWarning:\e[0m Shell windows has less than 120 columns. Go to options - Window and increate it."



	[ $loglevel -ge 0 ] && echo "" 
	initial_status_started=$(now_epoch)
	log_step_start "Rendering initial pipeline status"
	./custom_nodes/comfyui_stereoscopic/api/status.sh
	log_step_end "Rendering initial pipeline status" "$initial_status_started"
	[ $loglevel -ge 0 ] && echo " "

	# Precompute filesystem status once per iteration to avoid many lib_fs calls.
	# The Python scanner writes key=value pairs to `user/default/comfyui_stereoscopic/.fs_status.properties`.
	FS_STATUS_FILE="user/default/comfyui_stereoscopic/.fs_status.properties"
	export FS_STATUS_FILE
	# Resolve python executable (prefer embedded if PYTHON_BIN_PATH set)
	PY_EXEC="${PYTHON_BIN_PATH:-}""python.exe"
	if [ ! -x "$PY_EXEC" ]; then
		PY_EXEC=python
	fi

	# Read precomputed count from FS_STATUS_FILE. Keys: <type>|<path>=<count>
	read_fs_status() {
		typ="$1"
		dir="$2"
		case "$typ" in
			any)
				count_files_with_exts "$dir" any
				;;
			images)
				count_files_with_exts "$dir" images
				;;
			videos)
				count_files_with_exts "$dir" videos
				;;
			audio)
				count_files_with_exts "$dir" audio
				;;
			*)
				echo 0
				;;
		esac
	}

	INITIALRUN=TRUE
	TVAIREPORTED=-1
    # Treat first loop as a new FS status to trigger an initial autoforward
    FS_STATUS_NEW=1
	while true;
	do
		iteration_started=$(now_epoch)
		# Check for external soft-kill signal
		if [ ! -e user/default/comfyui_stereoscopic/.daemonactive ]; then
			break
		fi

		# (Filesystem scan moved later to be executed as late as possible before
		# the FS status comparison and autoforward trigger.)

    	# Check availablity of TVAI server
		tvai_check_started=$(now_epoch)
		if [ -e "$TVAI_BIN_DIR" ] && [ -e "$TVAI_MODEL_DIR" ] && [ $TVAIREPORTED -ne 0 ] ; then
			TMP_FILE=$(mktemp)
			curl --ssl-no-revoke -v -s -o - -I https://topazlabs.com/ >/dev/null 2>$TMP_FILE
			HTTP_CODE=`grep "HTTP/1.1 " $TMP_FILE | cut -d ' ' -f3`
			if [ -z "$HTTP_CODE" ] || [ $HTTP_CODE -ge 400 ] ; then
				if [ $TVAIREPORTED -lt 1 ] ; then
				TVAIREPORTED=1
				echo -e $"\e[93mWarning: TVAI server not present ( $HTTP_CODE ).\e[0m"
				sleep 4
				fi
			else
				if [ $TVAIREPORTED -gt 0 ] ; then
				echo -e $"\e[91mInfo:\e[0m TVAI server present again."
				fi
				TVAIREPORTED=0
			fi
			rm "$TMP_FILE"    
		fi
		log_step_if_slow "TVAI availability check" "$tvai_check_started" 2

		# Is there is a limit a TVAI login is valid? Enforce re-login before watermark is applied.
		#if [ -e "$TVAI_MODEL_DIR"/auth.tpz ] && [[ $(find "$TVAI_MODEL_DIR"/auth.tpz -mtime +40 -print) ]]; then
		#  echo "TVAI authentication exists but is older than 40 days - invalidated."
		#  mv -f -- "$TVAI_MODEL_DIR"/auth.tpz "$TVAI_MODEL_DIR"/auth-invalidated.tpz
		#fi

		tvai_login_started=
		if [ -e "$TVAI_BIN_DIR" ] && [ -e "$TVAI_MODEL_DIR" ] && [ ! -e "$TVAI_MODEL_DIR"/auth.tpz ] ; then
			tvai_login_started=$(now_epoch)
			log_step_start "Waiting for TVAI login"
		fi
		while [ -e "$TVAI_BIN_DIR" ] && [ -e "$TVAI_MODEL_DIR" ] && [ ! -e "$TVAI_MODEL_DIR"/auth.tpz ]  ; do
			export TVAI_MODEL_DIR
			"$TVAI_BIN_DIR"/login.exe
			read -p "LOGIN, THEN PRESS RETURN TO CONTINUE... " xy
						
			TVAI_BIN_DIR=$(awk -F "=" '/TVAI_BIN_DIR=/ {print $2}' $CONFIGFILE | head -n 1) ; TVAI_BIN_DIR=${TVAI_BIN_DIR:-""}
			TVAI_MODEL_DATA_DIR=$(awk -F "=" '/TVAI_MODEL_DATA_DIR=/ {print $2}' $CONFIGFILE) ; TVAI_MODEL_DATA_DIR=${TVAI_MODEL_DATA_DIR:-""}
			TVAI_MODEL_DIR=$(awk -F "=" '/TVAI_MODEL_DIR=/ {print $2}' $CONFIGFILE) ; TVAI_MODEL_DIR=${TVAI_MODEL_DIR:-""}			
		done
		if [ -n "$tvai_login_started" ] ; then
			log_step_end "Waiting for TVAI login" "$tvai_login_started"
		fi
	
		# happens every iteration since daemon is responsibe to initially create config and detect comfyui changes
		COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST=/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
		COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT=/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
		export COMFYUIHOST COMFYUIPORT

		[ $loglevel -ge 0 ] && [[ ! -z "$INITIALRUN" ]] && echo "Using ComfyUI on $COMFYUIHOST port $COMFYUIPORT" && INITIALRUN=

		# GLOBAL: move output to next stage input (This must happen in batch_all per stage, too)
		global_move_started=$(now_epoch)
		mkdir -p input/vr/scaling input/vr/fullsbs
		# scaling -> fullsbs
		GLOBIGNORE="*_fullsbs*.*"
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && mv -f -- output/vr/scaling/*.mp4 output/vr/scaling/*.png output/vr/scaling/*.jpg output/vr/scaling/*.jpeg output/vr/scaling/*.PNG output/vr/scaling/*.JPG output/vr/scaling/*.JPEG input/vr/fullsbs output/vr/scaling/*.webm output/vr/scaling/*.WEBM input/vr/fullsbs  >/dev/null 2>&1
		# slides -> fullsbs
		GLOBIGNORE="*_fullsbs*.*"
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && mv -f -- output/vr/slides/*.* input/vr/fullsbs  >/dev/null 2>&1
		# dubbing -> scaling
		#GLOBIGNORE="*_x?*.mp4"
		#[ $PIPELINE_AUTOFORWARD -ge 1 ] && mv -f -- output/vr/dubbing/sfx/*.mp4 input/vr/scaling  >/dev/null 2>&1
		
		unset GLOBIGNORE		

		# FAILSAFE
		mv -f -- input/vr/fullsbs/*_fullsbs*.* output/vr/fullsbs  >/dev/null 2>&1
		log_step_if_slow "Global pre-batch forwarding" "$global_move_started" 2
		
		status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
		if [ "$status" = "closed" ]; then
			echo -ne $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT\r"
			SERVERERROR="x"
		else
			if [[ ! -z $SERVERERROR ]]; then
				echo ""
				echo -e $"\e[92mComfyUI is serving again.\e[0m"
				SERVERERROR=
			fi
			
			count_started=$(now_epoch)
			SLIDECOUNT=$(read_fs_status images "input/vr/slides")
			SLIDESBSCOUNT=$(read_fs_status images "input/vr/slideshow")
			if [ -x "$(command -v nvidia-smi)" ]; then
				DUBSFXCOUNT=$(read_fs_status videos "input/vr/dubbing/sfx")
				DUBMUSICCOUNT=$(read_fs_status videos "input/vr/dubbing/music")
			else
				DUBSFXCOUNT=0
				DUBMUSICCOUNT=0
			fi
			SCALECOUNT=$(read_fs_status any "input/vr/scaling")
			SBSCOUNT=$(read_fs_status any "input/vr/fullsbs")
			OVERRIDECOUNT=$(read_fs_status any "input/vr/scaling/override")
			IGNORENAMECOUNT=$(read_fs_status any "input/vr/concat/ignorename")
			SINGLELOOPCOUNT=$(read_fs_status videos "input/vr/singleloop")
			INTERPOLATECOUNT=$(read_fs_status videos "input/vr/interpolate")
			CONCATCOUNT=$(read_fs_status videos "input/vr/concat")
			WMECOUNT=$(read_fs_status images "input/vr/watermark/encrypt")
			WMDCOUNT=$(read_fs_status images "input/vr/watermark/decrypt")
			CAPCOUNT=$(read_fs_status any "input/vr/caption")
			TASKCOUNT=$(compute_task_count_with_spinner)
			idle_waiting_append_dot_if_slow "$count_started" 2 || log_step_if_slow_verbose "Incoming file and task count refresh" "$count_started" 2


			
			if [ $WMECOUNT -gt 0 ] ; then
				WATERMARK_LABEL=$(awk -F "=" '/WATERMARK_LABEL=/ {print $2}' $CONFIGFILE) ; WATERMARK_LABEL=${WATERMARK_LABEL:-""}
				if [[ -z $WATERMARK_LABEL ]] ; then
					echo -e $"\e[93mWarning:\e[0m You must configure WATERMARK_LABEL in $CONFIGFILE to encrypt."
					WMECOUNT=0
				fi
			fi
			
			COUNT=$(( DUBSFXCOUNT + DUBMUSICCOUNT + SCALECOUNT + SBSCOUNT + OVERRIDECOUNT + SINGLELOOPCOUNT + INTERPOLATECOUNT + CONCATCOUNT + IGNORENAMECOUNT + WMECOUNT + WMDCOUNT + CAPCOUNT + TASKCOUNT ))
			COUNTWSLIDES=$(( SLIDECOUNT + $COUNT ))
			COUNTSBSSLIDES=$(( SLIDESBSCOUNT + $COUNT ))
			if [ -e user/default/comfyui_stereoscopic/.pipelinepause ] ; then
				idle_waiting_endline
				rm -f user/default/comfyui_stereoscopic/.pipelineactive 2>/dev/null
				BLINK=`shuf -n1 -e "..." "   "`
				[ $loglevel -ge 0 ] && echo -ne $"\e[93m\e[2m*** PAUSED (Use App to resume) *** $BLINK\e[0m \r"
				sleep 1
			elif [[ $COUNT -gt 0 ]] || [[ $SLIDECOUNT -gt 1 ]] || [[ $COUNTSBSSLIDES -gt 1 ]] ; then
				idle_waiting_endline
				[ $loglevel -ge 0 ] && echo "Found $COUNT files in incoming folders:                               "
				[ $loglevel -ge 0 ] && echo "$SLIDECOUNT slides , $SCALECOUNT + $OVERRIDECOUNT to scale >> $SBSCOUNT for sbs >> $SINGLELOOPCOUNT to loop >> $INTERPOLATECOUNT to interpolate, $SLIDECOUNT for slideshow >> $CONCATCOUNT to concat" && echo "$DUBSFXCOUNT to dub, $WMECOUNT to encrypt, $WMDCOUNT to decrypt, $CAPCOUNT for caption, $TASKCOUNT in tasks"

				touch user/default/comfyui_stereoscopic/.pipelineactive
				log_info "Preparation before batch_all took $(( $(now_epoch) - iteration_started ))s."

        		TVAIREPORTED=-1
				batch_all_started=$(now_epoch)
				log_step_start "Running batch_all for $COUNT queued inputs"
				./custom_nodes/comfyui_stereoscopic/api/batch_all.sh || exit 1
				log_step_end "Running batch_all" "$batch_all_started"
				[ $loglevel -ge 0 ] && echo "****************************************************"
				[ $loglevel -ge 0 ] && echo "Using ComfyUI on $COMFYUIHOST port $COMFYUIPORT"
				
				post_status_started=$(now_epoch)
				log_step_start "Refreshing status after batch_all"
				./custom_nodes/comfyui_stereoscopic/api/status.sh				
				log_step_end "Refreshing status after batch_all" "$post_status_started"
				[ $loglevel -ge 0 ] && echo " "
			else
				BLINK=`shuf -n1 -e "..." "   "`
				idle_waiting_show "$BLINK"
				rm -f user/default/comfyui_stereoscopic/.pipelineactive
				sleep 1
			fi
			
			PIPELINE_AUTOFORWARD=$(awk -F "=" '/PIPELINE_AUTOFORWARD=/ {print $2}' $CONFIGFILE) ; PIPELINE_AUTOFORWARD=${PIPELINE_AUTOFORWARD:-1}

			WORKFLOW_FORWARDER_COUNT=$(read_fs_status any "output/vr/tasks/forwarder")
			if [[ $WORKFLOW_FORWARDER_COUNT -gt 0 ]] ; then
				forwarder_started=$(now_epoch)
				idle_waiting_append_dot || log_step_start_verbose "Forwarding output from tasks/forwarder"
				sleep 1
				[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh tasks/forwarder || exit 1 )
				idle_waiting_append_dot || log_step_end_verbose "Forwarding output from tasks/forwarder" "$forwarder_started"
			fi
			WORKFLOW_RELEASED_COUNT=$(read_fs_status any "output/vr/check/released")
			if [[ $WORKFLOW_RELEASED_COUNT -gt 0 ]] ; then
				released_started=$(now_epoch)
				idle_waiting_append_dot || log_step_start_verbose "Forwarding output from check/released"
				sleep 1
				[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh check/released || exit 1 )
				idle_waiting_append_dot || log_step_end_verbose "Forwarding output from check/released" "$released_started"
			fi
			
			# Run scanner synchronously once per loop iteration just before the quick
			# comparison so the previous `.prev` copy is as recent as possible and we
			# detect changes (timestamp/content) quickly. Use a fast binary compare
			# (cmp -s) later when needed.
			scan_started=$(now_epoch)
			if [ -f "$FS_STATUS_FILE" ] ; then
				cp -f -- "$FS_STATUS_FILE" "$FS_STATUS_FILE".prev 2>/dev/null || true
			else
				rm -f -- "$FS_STATUS_FILE".prev 2>/dev/null || true
			fi

			"$PY_EXEC" ./custom_nodes/comfyui_stereoscopic/api/compute_fs_status.py >/dev/null 2>&1 || true

			log_step_if_slow "Filesystem scan before batch evaluation" "$scan_started" 2

			# QUICK compare previous and new FS status before using the flags.
			if [ -f "$FS_STATUS_FILE" ] && [ -f "$FS_STATUS_FILE".prev ]; then
				cmp -s "$FS_STATUS_FILE".prev "$FS_STATUS_FILE"
				rc=$?
				if [ "$rc" -eq 0 ]; then
					FS_STATUS_CHANGED=0
				elif [ "$rc" -eq 1 ]; then
					FS_STATUS_CHANGED=1
				else
					log_info "cmp error (rc=$rc) while comparing FS status; treating as changed"
					FS_STATUS_CHANGED=1
				fi
			else
				if [ -f "$FS_STATUS_FILE" ] && [ ! -f "$FS_STATUS_FILE".prev ]; then
					FS_STATUS_CHANGED=1
				else
					FS_STATUS_CHANGED=0
				fi
			fi

			# CHECK FOR "PIPELINE_AUTOFORWARD" ACTIVATION IN CONFIG AND DO A FULL FORWARD OVER ALL STAGES AND TASKS.
			# Trigger full forward when PIPELINE_AUTOFORWARD changed from 0 to 1 since the last loop iteration
			# OR when the filesystem status file changed since we last computed it, or when this is
			# the first loop iteration (FS_STATUS_NEW=1). The latter allows very fast detection of
			# newly produced outputs that must be forwarded.
			if ( [ "$PREV_PIPELINE_AUTOFORWARD" -eq 0 ] && [ "$PIPELINE_AUTOFORWARD" -ge 1 ] ) \
			   || ( [ "${FS_STATUS_CHANGED:-0}" -eq 1 ] && [ "$PIPELINE_AUTOFORWARD" -ge 1 ] ) \
			   || ( [ "${FS_STATUS_NEW:-0}" -eq 1 ] && [ "$PIPELINE_AUTOFORWARD" -ge 1 ] ) ; then
				idle_waiting_endline
				autoforward_started=$(now_epoch)
				log_step_start "Running autoforward cleanup across stages and tasks"
				do_autoforward
				log_step_end "Running autoforward cleanup across stages and tasks" "$autoforward_started"
				# reset the flags so we don't re-run autoforward on the same change
				FS_STATUS_CHANGED=0
				rm -f -- "$FS_STATUS_FILE".prev 2>/dev/null || true
				# clear the initial-new flag after first run
				unset FS_STATUS_NEW 2>/dev/null || true
			fi
			# update previous value for next iteration
			PREV_PIPELINE_AUTOFORWARD=$PIPELINE_AUTOFORWARD
			
		fi
		
	done #KILL ME
fi
[ $loglevel -ge 0 ] && set +x
