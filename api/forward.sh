#!/bin/bash
# handle tasks for images and videos in batch from all placed in subfolders of ComfyUI/input/vr/tasks 
# 
# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).


# relative or abolute path of ComfyUI folder in your ComfyUI_windows_portable
# Default: Executed in ComfyUI folder
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`

CheckProbeValue() {
    kopv="$1"
	
	key="${kopv%%[^a-z0-9_]*}"
	value2="${kopv##*[^a-z0-9_]}"
	# if [ -z "$key" ] ; then key="$value"; value=""; fi	# unitory op not used yet
	op="${kopv:${#key}}"
	op="${op::-${#value2}}"

	if [ "$key" = "vram" ] ; then
		value1=`"$PYTHON_BIN_PATH"python.exe custom_nodes/comfyui_stereoscopic/api/python/get_vram.py`
	elif [ "$key" = "tvai" ] ; then
		if [ -d "$TVAI_BIN_DIR" ] ; then value1="true" ; else value1="false" ; fi
	else
		temp=`grep "$key" user/default/comfyui_stereoscopic/.tmpprobe.txt`
		temp=${temp#*:}
		temp="${temp%,*}"
		temp="${temp%\"*}"
		temp="${temp#*\"}"
		if [ -z "$temp" ] || [[ "$temp" = *[a-zA-Z]* ]]; then
			value1="$temp"
		else  # numric expression
			value1="$(( $temp ))"
		fi
	fi

	if [ "$op" = "<" ] || [ "$op" = ">" ] ; then
		if [ "$op" = "<" ] ; then tmp="$value1" ; value1="$value2" ; value2="$tmp" ; fi
		if [ "$value1" -gt "$value2" ] ; then
			return 0
		else
			return -1
		fi
	elif [ "$op" = '!=' ] || [ "$op" = '=' ] ; then
		if [ "$value1" = "$value2" ] ; then
			[ "$op" = '=' ] && return 0 || return -1
		else
			[ "$op" = '=' ] && return -1 || return 0
		fi
	else
		echo -e $"\e[91mError:\e[0m Invalid operator $op in $forwarddef"
		exit 1
	fi
}


cd $COMFYUIPATH

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

if [ -e $CONFIGFILE ] ; then
	loglevel=$(awk -F "=" '/loglevel/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
	[ $loglevel -ge 2 ] && set -x
	TVAI_BIN_DIR=$(awk -F "=" '/TVAI_BIN_DIR/ {print $2}' $CONFIGFILE) ; TVAI_BIN_DIR=${TVAI_BIN_DIR:-""}
fi

if test $# -ne 1
then
    echo "Usage: $0 outputpath"
    echo "E.g.: $0 fullsbs"
	exit 1
else

	# Use Systempath for python by default, but set it explictly for comfyui portable.
	PYTHON_BIN_PATH=
	if [ -d "../python_embeded" ]; then
	  PYTHON_BIN_PATH=../python_embeded/
	fi
	
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
		
		while read -r destination; do
			conditionalrules=`echo "$destination" | sed -nr 's/.*\[(.*)\].*/\1/p'`
			destination=${destination#*]}
			if [ -z "$destination" ] ; then
				SKIPPING_EMPTY_LINE=	# just ignore this line
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
				
				mkdir -p user/default/comfyui_stereoscopic
				
				for i in ${inputrule//;/ }
				do
					for o in ${outputrule//;/ }
					do
						if [[ $i == $o ]] ; then
							if [[ $i == "video" ]] ; then
								FILES=`find output/vr/"$sourcestage" -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' -o -name '*.MP4' -o -name '*.WEBM'`
								for file in $FILES ; do
									RULEFAILED=
									if [ ! -z "$conditionalrules" ] ; then
										
										`"$FFMPEGPATHPREFIX"ffprobe -hide_banner -v error -select_streams V:0 -show_entries stream=bit_rate,width,height,r_frame_rate,duration,nb_frames,display_aspect_ratio -of json -i "$file" >user/default/comfyui_stereoscopic/.tmpprobe.txt`
										`"$FFMPEGPATHPREFIX"ffprobe -hide_banner -v error -select_streams a:0 -show_entries stream=codec_type -of json -i "$file" >>user/default/comfyui_stereoscopic/.tmpprobe.txt`
										
										for parameterkopv in $(echo $conditionalrules | sed "s/:/ /g")
										do
											CheckProbeValue "$parameterkopv"
											retval=$?
											if [ "$retval" != 0 ] ; then
												RULEFAILED="$parameterkopv"
												break
											fi
										done
									fi
									[ -z "$RULEFAILED" ] && mv -f -- $file input/vr/$destination 2>/dev/null
								done
							elif  [[ $i == "image" ]] ; then
								FILES=`find output/vr/"$sourcestage" -maxdepth 1 -type f -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' -o  -name '*.PNG' -o -name '*.JPG' -o -name '*.JPEG' -o -name '*.WEBP'`
								for file in $FILES ; do
									RULEFAILED=
									if [ ! -z "$conditionalrules" ] ; then
									
										`"$FFMPEGPATHPREFIX"ffprobe -hide_banner -v error -select_streams V:0 -show_entries stream=width,height -of json -i "$file" >user/default/comfyui_stereoscopic/.tmpprobe.txt`
										
										for parameterkopv in $(echo $conditionalrules | sed "s/:/ /g")
										do
											CheckProbeValue "$parameterkopv"
											retval=$?
											if [ "$retval" != 0 ] ; then
												RULEFAILED="$parameterkopv"
												break
											fi
										done
									fi
									[ -z "$RULEFAILED" ] && mv -f -- $file input/vr/$destination 2>/dev/null
								done
							else
								echo -e $"\e[93mWarning:\e[0m Unknown media match in forwarding ignored: $i"
							fi
						fi
					done
				done
				
			else
				echo -e $"\e[91mError:\e[0m Invalid stage path in $sourcestage""/forward.txt: input/vr/""$destination does not exist."
				exit 1
			fi
		done < $forwarddef
	fi
fi

exit 0

