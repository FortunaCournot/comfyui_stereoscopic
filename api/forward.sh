#!/bin/bash
# handle tasks for images and videos in batch from all placed in subfolders of ComfyUI/input/vr/tasks 
# 
# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).

LOGRULES=0

# relative or abolute path of ComfyUI folder in your ComfyUI_windows_portable
# Default: Executed in ComfyUI folder
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`

cd $COMFYUIPATH

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

if [ -e $CONFIGFILE ] ; then
	loglevel=$(awk -F "=" '/loglevel=/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
	[ $loglevel -ge 2 ] && set -x
	TVAI_BIN_DIR=$(awk -F "=" '/TVAI_BIN_DIR=/ {print $2}' $CONFIGFILE) ; TVAI_BIN_DIR=${TVAI_BIN_DIR:-""}
fi

PIPELINE_AUTOFORWARD=$(awk -F "=" '/PIPELINE_AUTOFORWARD=/ {print $2}' $CONFIGFILE) ; PIPELINE_AUTOFORWARD=${PIPELINE_AUTOFORWARD:-"0"}
if [ $PIPELINE_AUTOFORWARD -lt 1 ] ; then
	exit 0
fi

DEBUG_AUTOFORWARD_RULES=$(awk -F "=" '/DEBUG_AUTOFORWARD_RULES=/ {print $2}' $CONFIGFILE) ; DEBUG_AUTOFORWARD_RULES=${DEBUG_AUTOFORWARD_RULES:-"0"}
IMAGE_INDEX_LIMIT=$(awk -F "=" '/IMAGE_INDEX_LIMIT=/ {print $2}' $CONFIGFILE) ; IMAGE_INDEX_LIMIT=${IMAGE_INDEX_LIMIT:-3}

# Use Systempath for python by default, but set it explictly for comfyui portable.
PYTHON_BIN_PATH=
if [ -d "../python_embeded" ]; then
  PYTHON_BIN_PATH=../python_embeded/
fi

# FS status helper functions: update individual property keys in the FS status file
FS_STATUS_FILE=${FS_STATUS_FILE:-user/default/comfyui_stereoscopic/.fs_status.properties}

fs_key_from_dir() {
	# normalize dir to match keys written by compute_fs_status.py
	local dir="$1"
	dir="${dir#./}"
	dir="$(echo "$dir" | sed 's#\\#/#g')"
	dir="${dir%/}"
	# if moving into input/vr/<stage>/wait or /stop, use the parent stage dir
	case "$dir" in
		*/wait|*/stop) dir="${dir%/*}" ;;
	esac
	echo "$dir"
}

fs_update_prop() {
	# fs_update_prop "<type>|<path>" <delta>
	local key="$1"; local delta="$2"; local file="$FS_STATUS_FILE"
	[ -z "$key" ] && return 1
	tmpf=$(mktemp 2>/dev/null || echo "$file.tmp")
	if [ ! -f "$file" ]; then
		# initialize file with zero for this key
		echo "$key=0" > "$file"
	fi
	awk -F"=" -v k="$key" -v d="$delta" 'BEGIN{OFS=FS} $1==k{n=$2 + d; if(n<0) n=0; $2=n; found=1} {print} END{if(!found){n=d; if(n<0) n=0; print k"="n}}' "$file" > "$tmpf" && mv "$tmpf" "$file"
}

fs_adjust_move_counts() {
	# fs_adjust_move_counts <src_dir> <dest_dir> <filename>
	local src="$1"; local dest="$2"; local fname="$3"
	[ -z "$src" ] && return
	[ -z "$dest" ] && return
	lc="${fname,,}"
	typ="any"
	case "$lc" in
		*.png|*.jpg|*.jpeg|*.webp|*.gif) typ="images" ;;
		*.mp4|*.webm|*.ts|*.mkv|*.avi|*.mov) typ="videos" ;;
		*.flac|*.mp3|*.wav|*.aac|*.m4a) typ="audio" ;;
		*) typ="any" ;;
	esac
	srckey_dir=$(fs_key_from_dir "$src")
	destkey_dir=$(fs_key_from_dir "$dest")
	fs_update_prop "any|$srckey_dir" -1
	fs_update_prop "$typ|$srckey_dir" -1
	fs_update_prop "any|$destkey_dir" 1
	fs_update_prop "$typ|$destkey_dir" 1
}


CheckProbeValue() {
    kopv="$1"
	file="$2"
	
	key="${kopv%%[^a-z0-9_]*}"
	value2="${kopv##*[^a-z0-9_]}"
	# if [ -z "$key" ] ; then key="$value"; value=""; fi	# unitory op not used yet
	op="${kopv:${#key}}"
	op="${op::-${#value2}}"

	[ $LOGRULES -gt 0 ] && echo "CheckProbeValue $kopv"": '""$key""'""$op""'""$value2""'"
	
	if [ "$key" = "vram" ] ; then
		value1=`"$PYTHON_BIN_PATH"python.exe custom_nodes/comfyui_stereoscopic/api/python/get_vram.py`
	elif [ "$key" = "tvai" ] ; then
		if [ -d "$TVAI_BIN_DIR" ] ; then value1="true" ; else value1="false" ; fi
	elif [ "$key" = "sbs" ] ; then
		if [[ "$file" = *"_SBS_LR"* ]] ; then value1="true" ; else value1="false" ; fi
		if [[ "$file" = *"_SBS_LR"* ]] ; then echo "_SBS_LR check true for $file"; else echo "_SBS_LR check false for $file" ; fi
	elif [ "$key" = "image" ] ; then
		lcfile="${file,,}"
		if [[ "$lcfile" = *".png" ]] || [[ "$lcfile" = *".webp" ]] || [[ "$lcfile" = *".jpg" ]] || [[ "$lcfile" = *".jpeg" ]] || [[ "$lcfile" = *".gif" ]] ; then value1="true" ; else value1="false" ; fi
	elif [ "$key" = "video" ] ; then
		lcfile="${file,,}"
		if [[ "$lcfile" = *".mp4" ]] || [[ "$lcfile" = *".webm" ]] || [[ "$lcfile" = *".ts" ]] ; then value1="true" ; else value1="false" ; fi
	elif [ "$key" = "calculated_aspect" ] ; then
		temp=`grep "width" user/default/comfyui_stereoscopic/.tmpprobe.txt`
		temp=${temp#*:}
		temp="${temp%,*}"
		temp="${temp%\"*}"
		width="${temp#*\"}"
		temp=`grep "height" user/default/comfyui_stereoscopic/.tmpprobe.txt`
		temp=${temp#*:}
		temp="${temp%,*}"
		temp="${temp%\"*}"
		height="${temp#*\"}"
		if [ -z "$width" ] || [ -z "$height" ] ; then
			value1="1000"
		else
			value1="$(( 1000 * $width / $height ))"
		fi
	elif [ "$key" = "pixel" ] ; then
		temp=`grep "width" user/default/comfyui_stereoscopic/.tmpprobe.txt`
		temp=${temp#*:}
		temp="${temp%,*}"
		temp="${temp%\"*}"
		width="${temp#*\"}"
		temp=`grep "height" user/default/comfyui_stereoscopic/.tmpprobe.txt`
		temp=${temp#*:}
		temp="${temp%,*}"
		temp="${temp%\"*}"
		height="${temp#*\"}"
		if [ -z "$width" ] || [ -z "$height" ] ; then
			value1="-1"
		else
			value1="$(( $width * $height ))"
		fi
	else
		temp=`grep "$key" user/default/comfyui_stereoscopic/.tmpprobe.txt`
		temp=${temp#*:}
		temp="${temp%,*}"
		temp="${temp%\"*}"
		temp="${temp#*\"}"
		if [ -z "$temp" ] || [[ "$temp" = *[a-zA-Z]* ]]; then
			value1="$temp"
		elif [[ $temp = *"."* ]] ; then
			value1="$(( ${temp%.*} ))"
		else  # numeric expression
			value1="$(( $temp ))"
		fi
	fi

	if [ "$op" = "<" ] || [ "$op" = ">" ] ; then
		if [ -z "$value1" ] ; then value1=0 ; fi
		if [ "$op" = "<" ] ; then tmp="$value1" ; value1="$value2" ; value2="$tmp" ; fi
		if [ "$value1" -gt "$value2" ] ; then
			return 0
		else
			[ $LOGRULES -gt 0 ] && echo "Rule failed: $kopv for $file"": $value1 $op $value2"
			return -1
		fi
	elif [ "$op" = '!=' ] || [ "$op" = '=' ] ; then
		if [ "$value1" = "$value2" ] ; then
			[ $LOGRULES -gt 0 ] && [ "$op" != '=' ] && echo "Rule failed: $kopv for $file"": $value1 $op $value2"
			[ "$op" = '=' ] && return 0 || return -1
		else
			[ $LOGRULES -gt 0 ] && [ "$op" = '=' ] && echo "Rule failed: $kopv for $file"": $value1 $op $value2"
			[ "$op" = '=' ] && return -1 || return 0
		fi
	else
		echo -e $"\e[91mError:\e[0m Invalid operator $op in $forwarddef"
		exit 1
	fi
}



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
			if [ -e user/default/comfyui_stereoscopic/.pipelinepause ] ; then
				# paused.
				exit 0
			fi
		fi

		if [ ! -e $sourcedef ] ; then
			echo -e $"\e[91mError:\e[0m Missing source definition at $sourcedef"
			exit 0
		fi

		temp=`grep "\"output\":" $sourcedef`
		temp=${temp#*:}
		temp="${temp%\"*}"
		temp="${temp#*\"}"
		outputrule="${temp%,*}"
		[ $loglevel -ge 1 ] && echo "forward output rule = $outputrule"

		DELAY=0
		temp=`grep forward_delay $sourcedef`
		if [ ! -z "$temp" ] ; then
			temp=${temp#*:}
			temp="${temp%\"*}"
			DELAY="${temp#*\"}"
		fi
		
		forwarddef=output/vr/"$sourcestage"/forward.txt
		forwarddef=`realpath $forwarddef`

		while read -r destination; do
			destination=`echo $destination`
			[ !  -z "$destination" ] && [ "${destination:0:1}" = "#" ] && continue
			conditionalrules=`echo "$destination" | sed -nr 's/.*\[(.*)\].*/\1/p'`
			# extract wait flag (wait=true) from conditionalrules and remove it
			WAIT_FLAG=0
			if [ -n "$conditionalrules" ] ; then
				new_rules=""
				for token in $(echo "$conditionalrules" | sed "s/:/ /g") ; do
					if [ "$token" = "wait=true" ] ; then
						WAIT_FLAG=1
					else
						if [ -z "$new_rules" ] ; then
							new_rules="$token"
						else
							new_rules="$new_rules:$token"
						fi
					fi
				done
				conditionalrules="$new_rules"
			fi
			[ $LOGRULES -gt 0 ] && echo "Rule: '""$destination""'"
			[ $LOGRULES -gt 0 ] && echo "conditionalrules: '""$conditionalrules""' (wait=$WAIT_FLAG)"
			destination=${destination##*\]}
			[ $LOGRULES -gt 0 ] && echo "destination: '""$destination""'"
			mkdir -p input/vr/$destination 2>/dev/null
			# if wait flag set, create wait subfolder and use it as input target
			if [ "$WAIT_FLAG" -eq 1 ] ; then
				mkdir -p input/vr/$destination/wait 2>/dev/null
				DEST_INPUT_DIR="input/vr/$destination/wait"
			else
				DEST_INPUT_DIR="input/vr/$destination"
			fi
			if [ -z "$destination" ] ; then
				SKIPPING_EMPTY_LINE=	# just ignore this line
			elif [ -d input/vr/$destination ] ; then
				if [[ $destination == *"tasks/_"* ]] ; then
					userdestination=tasks/${destination#tasks/_}

					jsonFile="user/default/comfyui_stereoscopic/""$userdestination"".json"
					if [ ! -e "$jsonFile" ] ; then
						echo -e $"\e[91mError:\e[0m Invalid destination! Check $forwarddef"
						echo -e $"\e[91mError:\e[0m Missing task destination definition at $jsonFile"
						exit 0
					fi
					
					#[ $loglevel -ge 1 ] && echo "forwarding media to user's $destination"

					temp=`grep "\"input\":" user/default/comfyui_stereoscopic/"$userdestination".json`
					temp=${temp#*:}
					temp="${temp%\"*}"
					temp="${temp#*\"}"
					inputrule="${temp%,*}"
					
				elif [[ $destination == *"tasks/"* ]] ; then
				
					jsonFile="custom_nodes/comfyui_stereoscopic/config/""$destination"".json"
					if [ ! -e "$jsonFile" ] ; then
						echo -e $"\e[91mError:\e[0m Invalid destination! Check $forwarddef"
						echo -e $"\e[91mError:\e[0m Missing task destination definition at $jsonFile"
						exit 0
					fi

					#[ $loglevel -ge 1 ] && echo "forwarding media to $destination"
					
					temp=`grep "\"input\":" custom_nodes/comfyui_stereoscopic/config/"$destination".json`
					temp=${temp#*:}
					temp="${temp%\"*}"
					temp="${temp#*\"}"
					inputrule="${temp%,*}"
					
				else
					jsonFile="custom_nodes/comfyui_stereoscopic/config/stages/""$destination"".json"
					if [ ! -e  "$jsonFile" ] ; then
						echo -e $"\e[91mError:\e[0m Invalid destination! Check $forwarddef"
						echo -e $"\e[91mError:\e[0m Missing stage destination definition at $jsonFile"
						exit 0
					fi
					
					#[ $loglevel -ge 1 ] && echo "forwarding media to stage $destination"
					
					temp=`grep "\"input\":" custom_nodes/comfyui_stereoscopic/config/stages/"$destination".json`
					temp=${temp#*:}
					temp="${temp%\"*}"
					temp="${temp#*\"}"
					inputrule="${temp%,*}"
					
				fi
				
				[ $DEBUG_AUTOFORWARD_RULES -gt 0 ] && echo "forward input rule rules = $inputrule"
				
				mkdir -p user/default/comfyui_stereoscopic
				MOVEMSGPREFIX=$'\n'
				for i in ${inputrule//;/ }
				do
					for o in ${outputrule//;/ }
					do
            			[ $DEBUG_AUTOFORWARD_RULES -gt 0 ] && echo "$i :: $o"
						if [[ $i == $o ]] ; then
							if [[ $i == "video" ]] ; then
								OIFS="$IFS"
								IFS=$'\n'
								FILES=`find output/vr/"$sourcestage" -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' -o -name '*.MP4' -o -name '*.WEBM'`
								IFS="$OIFS"
								[ $DEBUG_AUTOFORWARD_RULES -gt 0 ] && [ -z "$FILES" ] && echo -e $"\e[2m""     $destination: no video files.\e[0m"
								for file in $FILES ; do
									RULEFAILED=
									if [ ! -z "$conditionalrules" ] ; then
										
										rm -f -- user/default/comfyui_stereoscopic/.tmpprobe.txt 2>/dev/null
										`"$FFMPEGPATHPREFIX"ffprobe -hide_banner -v error -select_streams V:0 -show_entries stream=bit_rate,width,height,r_frame_rate,duration,nb_frames,display_aspect_ratio -of json -i "$file" >user/default/comfyui_stereoscopic/.tmpprobe.txt`
										`"$FFMPEGPATHPREFIX"ffprobe -hide_banner -v error -select_streams a:0 -show_entries stream=codec_type -of json -i "$file" >>user/default/comfyui_stereoscopic/.tmpprobe.txt`
										
										[ $DEBUG_AUTOFORWARD_RULES -gt 0 ] && echo -e $"\e[2m""     $destination""($i) "$file":\e[0m"
										for parameterkopv in $(echo $conditionalrules | sed "s/:/ /g")
										do
											CheckProbeValue "$parameterkopv" "$file"
											retval=$?
											retname="ok"
											[ "$retval" != 0 ] && retname="invalid"
											[ $DEBUG_AUTOFORWARD_RULES -gt 0 ] && echo -e $"\e[2m""       "$parameterkopv" => $retname""\e[0m"
											if [ "$retval" != 0 ] ; then
												RULEFAILED="$parameterkopv"
												break
											fi
										done
									fi
								   	capfile="${file%.*}.txt"
													if [ -z "$RULEFAILED" ] && [ `stat --format=%Y "$file"` -le $(( `date +%s` - $DELAY )) ] ; then
														if mv -f -- "$file" "$DEST_INPUT_DIR" ; then
															echo "$MOVEMSGPREFIX""Moved ""$file"" --> $destination" && MOVEMSGPREFIX=
															fs_adjust_move_counts "output/vr/$sourcestage" "$DEST_INPUT_DIR" "$(basename -- "$file")"
														fi
														if [ -s "$capfile" ] ; then
															mv -f -- "$capfile" "$DEST_INPUT_DIR"
														fi
													fi
								done
							elif  [[ $i == "image" ]] ; then
								OIFS="$IFS"
								IFS=$'\n'
								FILES=`find output/vr/"$sourcestage" -maxdepth 1 -type f -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' -o  -name '*.PNG' -o -name '*.JPG' -o -name '*.JPEG' -o -name '*.WEBP'`
								IFS="$OIFS"
								[ $DEBUG_AUTOFORWARD_RULES -gt 0 ] && [ -z "$FILES" ] && echo -e $"\e[2m""     $destination: no image files.\e[0m"
								for file in $FILES ; do
									RULEFAILED=
									if [ ! -z "$conditionalrules" ] ; then
									
										rm -f -- user/default/comfyui_stereoscopic/.tmpprobe.txt 2>/dev/null
										`"$FFMPEGPATHPREFIX"ffprobe -hide_banner -v error -select_streams V:0 -show_entries stream=width,height -of json -i "$file" >user/default/comfyui_stereoscopic/.tmpprobe.txt`
										
										[ $DEBUG_AUTOFORWARD_RULES -gt 0 ] && echo -e $"\e[2m""     $destination""($i) "$file":\e[0m"
										for parameterkopv in $(echo $conditionalrules | sed "s/:/ /g")
										do
											CheckProbeValue "$parameterkopv" "$file"
											retval=$?
											retname="ok"
											[ "$retval" != 0 ] && retname="invalid"
											[ $DEBUG_AUTOFORWARD_RULES -gt 0 ] && echo -e $"\e[2m""       "$parameterkopv" => $retname""\e[0m"
											if [ "$retval" != 0 ] ; then
												RULEFAILED="$parameterkopv"
												break
											fi
										done
									fi
									capfile="${file%.*}.txt"
									if [ -z "$RULEFAILED" ] && [ `stat --format=%Y "$file"` -le $(( `date +%s` - $DELAY )) ] ; then
										TARGET_DIR="$DEST_INPUT_DIR"
										# if filename matches _<digits>_.ext pattern, and digits > IMAGE_INDEX_LIMIT,
										# move into wait subfolder instead of direct input
										fname=$(basename -- "$file")
										if [[ "$fname" =~ _([0-9]+)_\. ]]; then
											idx="${BASH_REMATCH[1]}"
											# force base-10 parsing for zero-padded numbers
											idx=$((10#$idx))
											if [ "$idx" -gt "$IMAGE_INDEX_LIMIT" ] ; then
												mkdir -p "input/vr/$destination/stop" 2>/dev/null
												TARGET_DIR="input/vr/$destination/stop"
											fi
										fi
										if mv -f -- "$file" "$TARGET_DIR" ; then
											echo "$MOVEMSGPREFIX""Moved ""$file"" --> $destination" && MOVEMSGPREFIX=
											fs_adjust_move_counts "output/vr/$sourcestage" "$TARGET_DIR" "$(basename -- "$file")"
										fi
										if [ -s "$capfile" ] ; then
											mv -f -- "$capfile" "$TARGET_DIR"
										fi
									fi
								done
								# If images are being forwarded but there is no rule to forward videos,
								# also move any video files found from the source stage into the
								# destination's OUTPUT folder (not into input). This preserves
								# videos when only image forwarding rules exist — but only when
								# source and destination are different.
								if ! echo " $inputrule " | grep -qw "video" ; then
									if [ "$sourcestage" = "$destination" ] ; then
										[ $DEBUG_AUTOFORWARD_RULES -gt 0 ] && echo -e $"\e[2m     skipping auto-move videos (same source/destination: $sourcestage)\e[0m"
									else
										mkdir -p output/vr/$destination 2>/dev/null
										OIFS="$IFS"
										IFS=$'\n'
										VFILES=`find output/vr/"$sourcestage" -maxdepth 1 -type f -iname '*.mp4' -o -iname '*.webm' -o -iname '*.ts' 2>/dev/null`
										IFS="$OIFS"
										[ $DEBUG_AUTOFORWARD_RULES -gt 0 ] && [ -z "$VFILES" ] && echo -e $"\e[2m""     $destination: no video files to auto-move to output.""\e[0m"
										for file in $VFILES ; do
											capfile="${file%.*}.txt"
											if [ `stat --format=%Y "$file"` -le $(( `date +%s` - $DELAY )) ] ; then
												if mv -f -- "$file" output/vr/$destination ; then
													echo "$MOVEMSGPREFIX""Moved ""$file"" --> output/$destination" && MOVEMSGPREFIX=
													fs_adjust_move_counts "output/vr/$sourcestage" "output/vr/$destination" "$(basename -- "$file")"
												fi
												[ -s "$capfile" ] && mv -f -- "$capfile" output/vr/$destination
											fi
										done
									fi
								fi
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
	else
		[ $loglevel -ge 1 ] &&  echo -e $"\e[2m""     no forward.txt file\e[0m"
	fi
fi

exit 0

