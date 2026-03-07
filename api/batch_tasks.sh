#!/bin/sh
# handle tasks for images and videos in batch from all placed in subfolders of ComfyUI/input/vr/tasks 
# 
# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).

onExit() {
	exit_code=$?
	exit $exit_code
}
trap onExit EXIT

get_json_value() {
	json_file="$1"
	json_key="$2"
	entry=`grep -oE "\"$json_key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$json_file" | head -n 1`
	if [ -z "$entry" ] ; then
		entry=`grep -oE "\"$json_key\"[[:space:]]*:[[:space:]]*[^,}]*" "$json_file" | head -n 1`
	fi
	if [ -z "$entry" ] ; then
		printf ''
		return 0
	fi
	value=`printf '%s' "$entry" | sed -E 's/^.*:[[:space:]]*//'`
	value=`printf '%s' "$value" | sed -E 's/[[:space:]]*$//'`
	value=${value#\"}
	value=${value%\"}
	printf '%s' "$value"
}

has_json_key() {
	json_file="$1"
	json_key="$2"
	grep -qE "\"$json_key\"[[:space:]]*:" "$json_file"
}

# Return epoch time in milliseconds (portable): prefer GNU date, fallback to python, else seconds*1000
now_ms() {
	if date +%s%3N >/dev/null 2>&1 ; then
		date +%s%3N
	elif command -v python3 >/dev/null 2>&1 ; then
		python3 - <<'PY'
import time
print(int(time.time()*1000))
PY
	elif command -v python >/dev/null 2>&1 ; then
		python - <<'PY'
import time
print(int(time.time()*1000))
PY
	else
		echo $(($(date +%s)*1000))
	fi
}

resolve_blueprint_placeholders_to_file() {
	source_json="$1"
	target_json="$2"
	cp -f -- "$source_json" "$target_json"

	declare -i guard=0
	while : ; do
		token=`grep -oE '%[A-Za-z_]+%' "$target_json" | head -n 1`
		if [ -z "$token" ] ; then
			break
		fi

		var_name=${token#%}
		var_name=${var_name%%%}

		first_value=`get_json_value "$target_json" "$var_name"`
		if [ -z "$first_value" ] ; then
			echo -e $"\e[91mError:\e[0m Placeholder $token unresolved. Key '$var_name' missing or empty in $source_json"
			return 1
		fi

		replacement="$first_value"
		if has_json_key "$target_json" "$first_value" ; then
			replacement=`get_json_value "$target_json" "$first_value"`
			if [ -z "$replacement" ] ; then
				echo -e $"\e[91mError:\e[0m Placeholder $token unresolved via key '$first_value' in $source_json"
				return 1
			fi
		fi

		token_escaped=`printf '%s' "$token" | sed -e 's/[^^]/[&]/g; s/\^/\\^/g'`
		replacement_escaped=`printf '%s' "$replacement" | sed -e 's/[\\&]/\\&/g'`
		sed -i "s/$token_escaped/$replacement_escaped/g" "$target_json"

		guard=$((guard + 1))
		if [ "$guard" -gt 100 ] ; then
			echo -e $"\e[93mWarning:\e[0m Placeholder resolving guard reached in $source_json"
			break
		fi
	done

	leftover=`grep -oE '%[A-Za-z_]+%' "$target_json" | head -n 1`
	if [ -n "$leftover" ] ; then
		echo -e $"\e[91mError:\e[0m Placeholder $leftover unresolved in $source_json"
		return 1
	fi
}

# relative or abolute path of ComfyUI folder in your ComfyUI_windows_portable
# Default: Executed in ComfyUI folder
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# relative to COMFYUIPATH:
SCRIPTFOLDERPATH=./custom_nodes/comfyui_stereoscopic/api/tasks

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

# Ensure loglevel is defined even if config file was just created
loglevel=${loglevel:-0}

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

FREESPACE=$(df -khBG . | tail -n1 | awk '{print $4}')
FREESPACE=${FREESPACE%G}
MINSPACE=10
status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
if [ ! -d ./custom_nodes/ComfyUI-MMAudio ]; then
    echo -e $"\e[91mError:\e[0mCustom nodes ComfyUI-MMAudio not present. Skipping."
elif [ ! -d ./models/mmaudio ]; then
    echo -e $"\e[91mError:\e[0mModels for ComfyUI-MMAudio not present. Skipping."
elif [ "$status" = "closed" ]; then
    echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
elif [[ $FREESPACE -lt $MINSPACE ]] ; then
	echo -e $"\e[91mError:\e[0m Less than $MINSPACE""G left on device: $FREESPACE""G"
elif test $# -ne 0 ; then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 "
    echo "E.g.: $0 "
else
	echo "Renaming files with spaces in input/vr/tasks to avoid issues..."
	{
		shopt -s nullglob
		for d in input/vr/tasks/*; do
			[ -d "$d" ] || continue
			# Rename only immediate children; use NUL delimiters for safety
			while IFS= read -r -d '' f; do
				new="${f// /_}"
				[ "$new" = "$f" ] && continue
				mv -- "$f" "$new"
			done < <(find "$d" -maxdepth 1 -mindepth 1 -name '* *' -print0 2>/dev/null)
		done
	} 2>/dev/null
	echo "Checking files in input/vr/tasks ..."

	if [ -z "$COMFYUIPATH" ]; then
		echo "Error: COMFYUIPATH not set in $(basename \"$0\") (cwd=$(pwd)). Start script from repository root."; exit 1;
	fi
	LIB_FS="$COMFYUIPATH/custom_nodes/comfyui_stereoscopic/api/lib_fs.sh"
	if [ -f "$LIB_FS" ]; then
		. "$LIB_FS" || { echo "Error: failed to source canonical $LIB_FS in $(basename \"$0\") (cwd=$(pwd))"; exit 1; }
	else
		echo "Error: required lib_fs not found at canonical path: $LIB_FS"; exit 1;
	fi

	# Enumerate task folders, then enumerate files directly inside each folder.
	# This avoids counting/caching mistakes (e.g. intermediate outputs) and is robust.
	declare -i INDEX=0
	processed_any=0
	echo "Starting batch processing of tasks in input/vr/tasks ..."
	shopt -s nullglob
	for d in input/vr/tasks/*/; do
		[ -d "$d" ] || continue
		TASKNAME=${d%/}
		TASKNAME=${TASKNAME##*/}
		# Skip internal folders
		if [ "$TASKNAME" = "intermediate" ] || [ "$TASKNAME" = "trashbin" ]; then
			continue
		fi

		# Skip tasks marked as unused/disabled in unused.properties (do this once per folder)
		if [[ "$TASKNAME" == _* ]] ; then
			cand1="tasks/$TASKNAME"
			cand2="tasks/${TASKNAME#_}"
		else
			cand1="tasks/$TASKNAME"
			cand2="tasks/_$TASKNAME"
		fi
		if is_disabled "$cand1" || is_disabled "$cand2" ; then
			[ $loglevel -ge 1 ] && echo "Skipping disabled task folder $cand1 / $cand2"
			continue
		fi

		# Count files directly in this task folder (used for progress like "X of COUNT")
		COUNT=$(find "$d" -maxdepth 1 -type f -name '*.*' 2>/dev/null | wc -l | awk '{print $1}')
		FOLDER_INDEX=0
		INDEX=0

		# Inner loop: files directly in this task folder that have a suffix (contain a dot)
		while IFS= read -r -d '' nextinputfile; do
			[ -e "$nextinputfile" ] || continue
			# pipelinepause must be checked at the start of the inner loop
			[ -e user/default/comfyui_stereoscopic/.pipelinepause ] && exit 0
			processed_any=1
			FOLDER_INDEX=$((FOLDER_INDEX + 1))

			INPUTDIR=`dirname -- "$nextinputfile"`
			# TASKNAME already known from outer loop (folder name)

			INDEX+=1
			echo "tasks/$TASKNAME" >user/default/comfyui_stereoscopic/.daemonstatus
			echo "$FOLDER_INDEX of $COUNT: ${nextinputfile##*/}" >>user/default/comfyui_stereoscopic/.daemonstatus
			newfn=${nextinputfile##*/}
			newfn=$INPUTDIR/${newfn//[^[:alnum:].-]/_}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			mv -- "$nextinputfile" $newfn 

			start_ms=$(now_ms)
			startiteration=$start_ms

			taskpath=${INPUTDIR##*/}
			DISPLAYNAME=$taskpath
			echo "$INDEX/$COUNT [$DISPLAYNAME]" >input/vr/tasks/BATCHPROGRESS.TXT
			
			if [[ $taskpath == "_"* ]] ; then
				jsonblueprint="user/default/comfyui_stereoscopic/tasks/"${taskpath:1}".json"
			else
				jsonblueprint="custom_nodes/comfyui_stereoscopic/config/tasks/"$taskpath".json"
			fi
			
			if [ -e "$jsonblueprint" ] ; then
				resolved_blueprint_dir="input/vr/tasks/intermediate/blueprint_resolved"
				cache_dir="input/vr/tasks/intermediate/blueprint_cache"
				resolved_jsonblueprint="$resolved_blueprint_dir/blueprint_resolved_${TASKNAME}_${INDEX}.json"
				effective_jsonblueprint="$jsonblueprint"
				mkdir -p "$resolved_blueprint_dir" "$cache_dir"
				# Try to use a cache based on file hash to skip resolving when unchanged
				cache_file="$cache_dir/$(basename "$jsonblueprint")"
				cache_hash_file="$cache_file.hash"
				# compute source hash (prefer sha1sum, fallback to md5sum)
				src_hash=''
				if command -v sha1sum >/dev/null 2>&1 ; then
					src_hash=$(sha1sum "$jsonblueprint" | awk '{print $1}')
				elif command -v md5sum >/dev/null 2>&1 ; then
					src_hash=$(md5sum "$jsonblueprint" | awk '{print $1}')
				fi
				if [ -n "$src_hash" ] && [ -f "$cache_file" ] && [ -f "$cache_hash_file" ] && [ "$(cat "$cache_hash_file")" = "$src_hash" ] ; then
					# cache hit: copy cached resolved blueprint
					cp -f -- "$cache_file" "$resolved_jsonblueprint"
					effective_jsonblueprint="$resolved_jsonblueprint"
					[ $loglevel -ge 2 ] && echo "Using cached resolved blueprint for $jsonblueprint"
				else
					# cache miss or no hashing available: resolve and update cache on success
					if resolve_blueprint_placeholders_to_file "$jsonblueprint" "$resolved_jsonblueprint" ; then
						if [ -s "$resolved_jsonblueprint" ] ; then
							effective_jsonblueprint="$resolved_jsonblueprint"
							# update cache
							cp -f -- "$resolved_jsonblueprint" "$cache_file"
							if [ -n "$src_hash" ] ; then
								echo "$src_hash" > "$cache_hash_file"
							fi
						else
							echo -e $"\e[93mWarning:\e[0m Resolved blueprint empty. Fallback to original: $jsonblueprint"
						fi
					else
						echo -e $"\e[93mWarning:\e[0m Placeholder resolve failed. Fallback to original: $jsonblueprint"
					fi
				fi

				# handle only current version
				taskversion="-1"
				# extract numeric version robustly from JSON (prefer digits only)
				if [ -f "$effective_jsonblueprint" ]; then
					ver_line=$(grep -oE '"version"[[:space:]]*:[[:space:]]*[0-9]+' "$effective_jsonblueprint" | head -n1 || true)
					if [ -n "$ver_line" ]; then
						taskversion=$(printf '%s' "$ver_line" | sed -E 's/.*:[[:space:]]*//')
					else
						# fallback: quoted numeric version
						ver_line=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[0-9]+"' "$effective_jsonblueprint" | head -n1 || true)
						if [ -n "$ver_line" ]; then
							taskversion=$(printf '%s' "$ver_line" | sed -E 's/.*:[[:space:]]*"([0-9]+)"/\1/')
						fi
					fi
				fi
				CURRENTVERSION=1
				if printf '%s' "$taskversion" | grep -qE '^[0-9]+$' && [ "$taskversion" -eq "$CURRENTVERSION" ] ; then
					blueprint=`cat "$effective_jsonblueprint" | grep -o '"blueprint":[^"]*"[^"]*"' | sed -E 's/".*".*"(.*)"/\1/'`
					blueprint=${blueprint##*/}
					blueprint=${blueprint//[^[:alnum:].-]/_}
					blueprint=${blueprint// /_}
					blueprint=${blueprint//\(/_}
					blueprint=${blueprint//\)/_}
					scriptpath=$SCRIPTFOLDERPATH/$blueprint".sh"

					if [ -z "$blueprint" ] || [ "$blueprint" = "none" ] ; then
						OUTPUTDIR="output/vr/tasks/""$taskpath"
						mkdir -p "$OUTPUTDIR"
						mv -fv -- "$newfn" "$OUTPUTDIR"
					elif [ -e $scriptpath ] ; then
						/bin/bash $scriptpath "$effective_jsonblueprint" "$TASKNAME" "$newfn" || exit 1
					else
						echo -e $"\e[91mError:\e[0m Invalid blueprint in $jsonblueprint . script missing: $SCRIPTFOLDERPATH/$blueprint"".sh"
						exit 1
					fi
				else
					echo -e $"\e[91mError:\e[0m Invalid task version in $jsonblueprint   $taskversion != $CURRENTVERSION"
					exit 1
				fi
			else
				if [ $loglevel -ge 1 ] ; then
					echo -e $"\e[93mWarning:\e[0m No blueprint for task $DISPLAYNAME at `realpath $jsonblueprint`"
				fi
				mkdir -p "input/vr/tasks/$TASKNAME/error"
				if [ -e "$newfn" ] ; then
					mv -vf -- "$newfn" "input/vr/tasks/$TASKNAME/error"
				fi
				exit 0
			fi

			# Log iteration duration (ms) and task name when loglevel >= 1
			end_ms=$(now_ms)
			elapsed_ms=$((end_ms - start_ms))
			if [ ${loglevel:-0} -ge 1 ] ; then
				echo "Iteration $INDEX tasks/$TASKNAME took ${elapsed_ms} ms"
			fi
		done < <(find "$d" -maxdepth 1 -type f -name '*.*' -print0 2>/dev/null)
		rm -f user/default/comfyui_stereoscopic/.daemonstatus 2>/dev/null
		rm -f input/vr/tasks/BATCHPROGRESS.TXT 2>/dev/null
	done
	rm -f user/default/comfyui_stereoscopic/.daemonstatus 2>/dev/null
	rm -f input/vr/tasks/BATCHPROGRESS.TXT 2>/dev/null
	echo "Batch done."

fi
exit 0

