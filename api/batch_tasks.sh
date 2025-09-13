#!/bin/sh
# handle tasks for images and videos in batch from all placed in subfolders of ComfyUI/input/vr/tasks 
# 
# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).

onExit() {
	exit_code=$?
	exit $exit_code
}
trap onExit EXIT

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
			INPUTDIR=`dirname -- $nextinputfile`
			TASKNAME=${INPUTDIR##*/}

			INDEX+=1
			echo "tasks/$TASKNAME" >user/default/comfyui_stereoscopic/.daemonstatus
			echo "$INDEX of $COUNT" >>user/default/comfyui_stereoscopic/.daemonstatus
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
				# handle only current version
				taskversion="-1"
				taskversion=`cat "$jsonblueprint" | grep -o '"version":[^"]*"[^"]*"' | sed -E 's/".*".*"(.*)"/\1/'`
				CURRENTVERSION=1
				if [ $taskversion -eq $CURRENTVERSION ] ; then
					blueprint=`cat "$jsonblueprint" | grep -o '"blueprint":[^"]*"[^"]*"' | sed -E 's/".*".*"(.*)"/\1/'`
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
						/bin/bash $scriptpath "$jsonblueprint" "$TASKNAME" "$newfn" || exit 1
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
				exit 1
			fi
		done
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
	fi
	rm -f input/vr/tasks/BATCHPROGRESS.TXT
	echo "Batch done."

fi
exit 0

