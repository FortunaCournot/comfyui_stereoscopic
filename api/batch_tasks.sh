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
	for d in input/vr/tasks/*; do for f in $d/*\ *; do mv -- "$f" "${f// /_}"; done; done 2>/dev/null

	COUNT=`find input/vr/tasks/*/ -maxdepth 1 -type f | wc -l`
	declare -i INDEX=0
	if [[ $COUNT -gt 0 ]] ; then
		TASKFILES=`find input/vr/tasks/*/ -maxdepth 1 -type f`
		for nextinputfile in $TASKFILES ; do
			[ -e user/default/comfyui_stereoscopic/.pipelinepause ] && exit 0

			INPUTDIR=`dirname -- $nextinputfile`
			TASKNAME=${INPUTDIR##*/}

			INDEX+=1
			echo "tasks/$TASKNAME" >user/default/comfyui_stereoscopic/.daemonstatus
			echo "$INDEX of $COUNT: ${nextinputfile##*/}" >>user/default/comfyui_stereoscopic/.daemonstatus
			newfn=${nextinputfile##*/}
			newfn=$INPUTDIR/${newfn//[^[:alnum:].-]/_}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			mv -- "$nextinputfile" $newfn 

			start=`date +%s`
			end=`date +%s`
			startiteration=$start

			taskpath=${INPUTDIR##*/}
			DISPLAYNAME=$taskpath
			echo "$INDEX/$COUNT $DISPLAYNAME" >input/vr/tasks/BATCHPROGRESS.TXT
			
			if [[ $taskpath == "_"* ]] ; then
				jsonblueprint="user/default/comfyui_stereoscopic/tasks/"${taskpath:1}".json"
			else
				jsonblueprint="custom_nodes/comfyui_stereoscopic/config/tasks/"$taskpath".json"
			fi
			
			if [ -e "$jsonblueprint" ] ; then
				resolved_blueprint_dir="input/vr/tasks/intermediate/blueprint_resolved"
				resolved_jsonblueprint="$resolved_blueprint_dir/blueprint_resolved_${TASKNAME}_${INDEX}.json"
				effective_jsonblueprint="$jsonblueprint"
				mkdir -p "$resolved_blueprint_dir"
				if resolve_blueprint_placeholders_to_file "$jsonblueprint" "$resolved_jsonblueprint" ; then
					if [ -s "$resolved_jsonblueprint" ] ; then
						effective_jsonblueprint="$resolved_jsonblueprint"
					else
						echo -e $"\e[93mWarning:\e[0m Resolved blueprint empty. Fallback to original: $jsonblueprint"
					fi
				else
					echo -e $"\e[93mWarning:\e[0m Placeholder resolve failed. Fallback to original: $jsonblueprint"
				fi

				# handle only current version
				taskversion="-1"
				taskversion=`cat "$effective_jsonblueprint" | grep -o '"version":[^"]*"[^"]*"' | sed -E 's/".*".*"(.*)"/\1/'`
				CURRENTVERSION=1
				if [ $taskversion -eq $CURRENTVERSION ] ; then
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
				echo -e $"\e[91mError:\e[0m No blueprint for task $DISPLAYNAME at `realpath $jsonblueprint`"
				mkdir -p "input/vr/tasks/$TASKNAME/error"
				if [ -e "$newfn" ] ; then
					mv -vf -- "$newfn" "input/vr/tasks/$TASKNAME/error"
				fi
				exit 0
			fi
		done
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
	fi
	rm -f input/vr/tasks/BATCHPROGRESS.TXT
	echo "Batch done."

fi
exit 0

