#!/bin/sh
# handle tasks for images and videos in batch from all placed in subfolders of ComfyUI/input/vr/tasks 
# 
# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).


# relative or abolute path of ComfyUI folder in your ComfyUI_windows_portable
# Default: Executed in ComfyUI folder
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`

cd $COMFYUIPATH

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

if [ -e $CONFIGFILE ] ; then
	loglevel=$(awk -F "=" '/loglevel/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
	[ $loglevel -ge 2 ] && set -x
fi

if test $# -ne 1
then
    echo "Usage: $0 outputpath"
    echo "E.g.: $0 fullsbs"
	exit 1
else
	sourcestage=$1
	
	if [ -e output/vr/"$sourcestage"/forward.txt ] ; then

		#[ $loglevel -ge 1 ] && echo "sourcestage: '$sourcestage'"
	
		if [[ $sourcestage == *"tasks/_"* ]] ; then
			usersourcestage=tasks/${sourcestage#tasks/_}
			sourcedef=user/default/comfyui_stereoscopic/"$usersourcestage".json
		elif [[ $sourcestage == *"tasks/"* ]] ; then
			sourcedef=custom_nodes/comfyui_stereoscopic/config/"$sourcestage".json
		else
			sourcedef=custom_nodes/comfyui_stereoscopic/config/stages/"$sourcestage".json
		fi

		if [ ! -e $sourcedef ] ; then
			echo -e $"\e[91mError:\e[0m Missing source definition at $sourcedef"
			exit 0
		fi

		temp=`grep output $sourcedef`
		temp=${temp#*:}
		temp="${temp%\"*}"
		temp="${temp#*\"}"
		outputrule="${temp%,*}"
		#[ $loglevel -ge 1 ] && echo "forward output rule = $outputrule"

		forwarddef=output/vr/"$sourcestage"/forward.txt
		forwarddef=`realpath $forwarddef`
		destination=`cat $forwarddef`
		if [ -z "$destination" ] ; then
			echo -e $"\e[91mError:\e[0m Invalid stage path in $sourcestage""/forward.txt: file empty."
			exit 0
		elif [ -d input/vr/$destination ] ; then

			[[ $destination == *"tasks/_"* ]] && echo 3
			[[ $destination == *"tasks/"* ]] && echo 4

			if [[ $destination == *"tasks/_"* ]] ; then
				userdestination=tasks/${destination#tasks/_}

				if [ ! -e user/default/comfyui_stereoscopic/"$userdestination".json ] ; then
					echo -e $"\e[91mError:\e[0m Invalid destination! Check $forwarddef"
					echo -e $"\e[91mError:\e[0m Missing task destination definition at user/default/comfyui_stereoscopic/"$userdestination".json"
					exit 0
				fi
				
				#[ $loglevel -ge 1 ] && echo "forwarding media to user's $destination"

				temp=`grep input user/default/comfyui_stereoscopic/"$userdestination".json`
				temp=${temp#*:}
				temp="${temp%\"*}"
				temp="${temp#*\"}"
				inputrule="${temp%,*}"
				
			elif [[ $destination == *"tasks/"* ]] ; then
			
				if [ ! -e custom_nodes/comfyui_stereoscopic/config/"$destination".json ] ; then
					echo -e $"\e[91mError:\e[0m Invalid destination! Check $forwarddef"
					echo -e $"\e[91mError:\e[0m Missing task destination definition at custom_nodes/comfyui_stereoscopic/config/"$destination".json"
					exit 0
				fi

				#[ $loglevel -ge 1 ] && echo "forwarding media to $destination"
				
				temp=`grep input custom_nodes/comfyui_stereoscopic/config/"$destination".json`
				temp=${temp#*:}
				temp="${temp%\"*}"
				temp="${temp#*\"}"
				inputrule="${temp%,*}"
				
			else
				if [ ! -e custom_nodes/comfyui_stereoscopic/config/stages/"$destination".json ] ; then
					echo -e $"\e[91mError:\e[0m Invalid destination! Check $forwarddef"
					echo -e $"\e[91mError:\e[0m Missing stage destination definition at custom_nodes/comfyui_stereoscopic/config/stages/"$destination".json"
					exit 0
				fi
				
				#[ $loglevel -ge 1 ] && echo "forwarding media to stage $destination"
				
				temp=`grep input custom_nodes/comfyui_stereoscopic/config/stages/"$destination".json`
				temp=${temp#*:}
				temp="${temp%\"*}"
				temp="${temp#*\"}"
				inputrule="${temp%,*}"
				
			fi
			
			#[ $loglevel -ge 1 ] && echo "forward input rule rules = $inputrule"
			
			for i in ${inputrule//;/ }
			do
				for o in ${outputrule//;/ }
				do
					if [[ $i == $o ]] ; then
						if [[ $i == "video" ]] ; then
							mv -f -- output/vr/"$sourcestage"/*.mp4 output/vr/"$sourcestage"/*.webm output/vr/"$sourcestage"/*.MP4 output/vr/"$sourcestage"/*.WEBM input/vr/$destination 2>/dev/null
						elif  [[ $i == "image" ]] ; then
							mv -f -- output/vr/"$sourcestage"/*.png output/vr/"$sourcestage"/*.jpg output/vr/"$sourcestage"/*.jpeg output/vr/"$sourcestage"/*.webp output/vr/"$sourcestage"/*.PNG output/vr/"$sourcestage"/*.JPG output/vr/"$sourcestage"/*.JPEG output/vr/"$sourcestage"/*.WEBP input/vr/$destination 2>/dev/null
						else
							echo -e $"\e[93mWarning:\e[0m Unknown media match in forwarding ignored: $i"
						fi
					fi
				done
			done
			
		else
			echo -e $"\e[91mError:\e[0m Invalid stage path in $sourcestage""/forward.txt: input/vr/""$destination does not exist."
			exit 0
		fi
	fi
fi

exit 0

