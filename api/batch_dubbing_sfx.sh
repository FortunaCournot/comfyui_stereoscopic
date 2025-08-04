#!/bin/sh
# Upscales videos in batch from all base videos placed in ComfyUI/input/vr/dubbing/sfx (input)
# 
# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).


# relative or abolute path of ComfyUI folder in your ComfyUI_windows_portable
# Default: Executed in ComfyUI folder
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# relative to COMFYUIPATH:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/v2v_dubbing_sfx.sh 

cd $COMFYUIPATH

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

export CONFIGFILE
if [ -e $CONFIGFILE ] ; then
	loglevel=$(awk -F "=" '/loglevel/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
	[ $loglevel -ge 2 ] && set -x
    config_version=$(awk -F "=" '/config_version/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
	COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
	COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
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
    echo -e $"\e[93mWarning:\e[0mCustom nodes ComfyUI-MMAudio not present. Skipping."
elif [ ! -d ./models/mmaudio ]; then
    echo -e $"\e[93mWarning:\e[0mModels for ComfyUI-MMAudio not present. Skipping."
elif [ "$status" = "closed" ]; then
    echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
elif [[ $FREESPACE -lt $MINSPACE ]] ; then
	echo -e $"\e[91mError:\e[0m Less than $MINSPACE""G left on device: $FREESPACE""G"
elif test $# -ne 0 ; then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 "
    echo "E.g.: $0 "
else
	
	COUNT=`find input/vr/dubbing/sfx -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' | wc -l`
	declare -i INDEX=0
	if [[ $COUNT -gt 0 ]] ; then
		VIDFILES=`find input/vr/dubbing/sfx -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm'`
		for nextinputfile in $VIDFILES ; do
			INDEX+=1
			echo "$INDEX/$COUNT" >input/vr/dubbing/sfx/BATCHPROGRESS.TXT
			newfn=${nextinputfile//[^[:alnum:.]]/}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			mv "$nextinputfile" $newfn 

			start=`date +%s`
			end=`date +%s`
			startiteration=$start
			
			/bin/bash $SCRIPTPATH "$newfn"
			
			status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
			if [ "$status" = "closed" ]; then
				echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
				exit
			fi
			
			echo "Waiting for queue to finish..."
			sleep 3  # Give some extra time to start...
			lastcount=""
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
			end=`date +%s`
			runtime=$((end-startiteration))
			echo -e $"\e[92mdone.\e[0m duration: $runtime""s                        "
			rm queuecheck.json
				
		done
	fi
	rm -f input/vr/dubbing/sfx/BATCHPROGRESS.TXT
	echo "Batch done."

fi

