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

# Marker for GUI to show that forward.sh is currently active.
FORWARD_ACTIVE_LOCK=./user/default/comfyui_stereoscopic/.forwardactive
FORWARD_LASTRUN_FILE=./user/default/comfyui_stereoscopic/forward_last_run.properties
FORWARD_RULE_CACHE_DIR=./user/default/comfyui_stereoscopic/forward_rule_cache
FORWARD_LASTRUN_REF=

declare -A FORWARD_INPUT_RULE_CACHE
declare -A FORWARD_OUTPUT_RULE_CACHE
declare -A FORWARD_DELAY_CACHE

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

# Ensure FS status file exists so forward's incremental updates don't operate on an empty file
PY_EXEC="${PYTHON_BIN_PATH}python.exe"
if [ ! -x "$PY_EXEC" ]; then
	if command -v python3 >/dev/null 2>&1 ; then
		PY_EXEC=python3
	elif command -v python >/dev/null 2>&1 ; then
		PY_EXEC=python
	fi
fi
if [ ! -f "$FS_STATUS_FILE" ] && [ -n "$PY_EXEC" ]; then
	"$PY_EXEC" ./custom_nodes/comfyui_stereoscopic/api/compute_fs_status.py >/dev/null 2>&1 || true
fi

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

forward_last_run_read() {
	local key="$1"
	[ -f "$FORWARD_LASTRUN_FILE" ] || return 0
	awk -F "=" -v k="$key" '$1==k { print $2; exit }' "$FORWARD_LASTRUN_FILE"
}

forward_last_run_write() {
	local key="$1"
	local value="$2"
	local tmpf

	mkdir -p ./user/default/comfyui_stereoscopic 2>/dev/null || true
	tmpf=$(mktemp 2>/dev/null || echo "$FORWARD_LASTRUN_FILE.tmp")
	if [ -f "$FORWARD_LASTRUN_FILE" ] ; then
		awk -F "=" -v k="$key" -v v="$value" 'BEGIN{OFS=FS} $1==k {$2=v; found=1} {print} END{if(!found) print k, v}' "$FORWARD_LASTRUN_FILE" > "$tmpf" && mv "$tmpf" "$FORWARD_LASTRUN_FILE"
	else
		echo "$key=$value" > "$tmpf"
		mv "$tmpf" "$FORWARD_LASTRUN_FILE"
	fi
}

should_skip_old_forward_file() {
	local file="$1"
	local file_mtime
	[ -n "$FORWARD_LASTRUN_TS" ] || return 1
	file_mtime=$(stat --format=%Y "$file" 2>/dev/null) || return 1
	[ "$file_mtime" -le "$FORWARD_LASTRUN_TS" ]
}

json_cache_key() {
	local path="$1"
	path="${path#./}"
	path="${path//\\//}"
	echo "${path//[^[:alnum:]._-]/_}"
}

json_file_mtime() {
	stat --format=%Y "$1" 2>/dev/null
}

load_json_rule_cache() {
	local json_file="$1"
	local cache_key="$2"
	local cache_file json_mtime input_value output_value delay_value

	if [ -n "${FORWARD_INPUT_RULE_CACHE[$cache_key]+x}" ] ; then
		return 0
	fi

	json_mtime=$(json_file_mtime "$json_file") || return 1
	mkdir -p "$FORWARD_RULE_CACHE_DIR" 2>/dev/null || true
	cache_file="$FORWARD_RULE_CACHE_DIR/$(json_cache_key "$json_file").properties"

	if [ -f "$cache_file" ] ; then
		unset CACHE_MTIME CACHE_INPUT_RULE CACHE_OUTPUT_RULE CACHE_FORWARD_DELAY
		. "$cache_file"
		if [ "${CACHE_MTIME:-}" = "$json_mtime" ] ; then
			FORWARD_INPUT_RULE_CACHE[$cache_key]="${CACHE_INPUT_RULE:-}"
			FORWARD_OUTPUT_RULE_CACHE[$cache_key]="${CACHE_OUTPUT_RULE:-}"
			FORWARD_DELAY_CACHE[$cache_key]="${CACHE_FORWARD_DELAY:-0}"
			return 0
		fi
	fi

	input_value=$(awk -F '"' '/"input"[[:space:]]*:/ {print $4; exit}' "$json_file")
	output_value=$(awk -F '"' '/"output"[[:space:]]*:/ {print $4; exit}' "$json_file")
	delay_value=$(awk -F '[:",]' '/forward_delay/ {gsub(/[[:space:]]/, "", $2); if ($2 != "") { print $2; exit }}' "$json_file")
	delay_value=${delay_value:-0}

	FORWARD_INPUT_RULE_CACHE[$cache_key]="$input_value"
	FORWARD_OUTPUT_RULE_CACHE[$cache_key]="$output_value"
	FORWARD_DELAY_CACHE[$cache_key]="$delay_value"

	printf 'CACHE_MTIME=%q\nCACHE_INPUT_RULE=%q\nCACHE_OUTPUT_RULE=%q\nCACHE_FORWARD_DELAY=%q\n' \
		"$json_mtime" "$input_value" "$output_value" "$delay_value" > "$cache_file"
}

forward_path_changed_since_last_run() {
	local path="$1"
	local path_mtime
	[ -n "$FORWARD_LASTRUN_TS" ] || return 0
	[ -e "$path" ] || return 1
	path_mtime=$(stat --format=%Y "$path" 2>/dev/null) || return 1
	[ "$path_mtime" -gt "$FORWARD_LASTRUN_TS" ]
}

has_forward_media_candidates() {
	local dir="$1"
	local dir_mtime
	[ -d "$dir" ] || return 1
	if [ -n "$FORWARD_LASTRUN_TS" ] ; then
		dir_mtime=$(stat --format=%Y "$dir" 2>/dev/null) || dir_mtime=
		if [ -n "$dir_mtime" ] && [ "$dir_mtime" -le "$FORWARD_LASTRUN_TS" ] ; then
			return 1
		fi
	fi
	if [ -n "$FORWARD_LASTRUN_REF" ] && [ -e "$FORWARD_LASTRUN_REF" ] ; then
		find "$dir" -maxdepth 1 -type f \( -iname '*.mp4' -o -iname '*.webm' -o -iname '*.ts' -o -iname '*.mkv' -o -iname '*.avi' -o -iname '*.mov' -o -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.gif' \) -newer "$FORWARD_LASTRUN_REF" -print -quit 2>/dev/null | grep -q .
		return $?
	fi
	find "$dir" -maxdepth 1 -type f \( -iname '*.mp4' -o -iname '*.webm' -o -iname '*.ts' -o -iname '*.mkv' -o -iname '*.avi' -o -iname '*.mov' -o -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.gif' \) -print -quit 2>/dev/null | grep -q .
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
	FORWARD_LASTRUN_TS=$(forward_last_run_read "$sourcestage")
	if ! printf '%s' "$FORWARD_LASTRUN_TS" | grep -Eq '^[0-9]+$' ; then
		FORWARD_LASTRUN_TS=
	else
		FORWARD_LASTRUN_REF=$(mktemp 2>/dev/null || echo "./user/default/comfyui_stereoscopic/.forward_last_run_$$.tmp")
		if ! touch -d "@$FORWARD_LASTRUN_TS" "$FORWARD_LASTRUN_REF" 2>/dev/null ; then
			rm -f -- "$FORWARD_LASTRUN_REF" 2>/dev/null
			FORWARD_LASTRUN_REF=
		fi
	fi
	
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

		# Mark forward activity for the GUI and guarantee cleanup.
		mkdir -p ./user/default/comfyui_stereoscopic 2>/dev/null || true
		touch "$FORWARD_ACTIVE_LOCK" 2>/dev/null || true
		cleanup_forward_active() {
			rm -f "$FORWARD_ACTIVE_LOCK" 2>/dev/null || true
			[ -n "$FORWARD_LASTRUN_REF" ] && rm -f "$FORWARD_LASTRUN_REF" 2>/dev/null || true
		}
		trap cleanup_forward_active EXIT INT TERM

		forwarddef=output/vr/"$sourcestage"/forward.txt
		forwarddef=`realpath $forwarddef`
		FORWARD_SOURCE_DIR="output/vr/$sourcestage"
		if [ -n "$FORWARD_LASTRUN_TS" ] \
			&& ! forward_path_changed_since_last_run "$sourcedef" \
			&& ! forward_path_changed_since_last_run "$forwarddef" \
			&& ! has_forward_media_candidates "$FORWARD_SOURCE_DIR" ; then
			exit 0
		fi

		load_json_rule_cache "$sourcedef" "$sourcedef" || exit 1
		outputrule="${FORWARD_OUTPUT_RULE_CACHE[$sourcedef]}"
		[ $loglevel -ge 2 ] && echo "forward output rule = $outputrule"

		DELAY="${FORWARD_DELAY_CACHE[$sourcedef]:-0}"

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
				json_cache_key_path=
				if [[ $destination == *"tasks/_"* ]] ; then
					userdestination=tasks/${destination#tasks/_}

					jsonFile="user/default/comfyui_stereoscopic/""$userdestination"".json"
					if [ ! -e "$jsonFile" ] ; then
						echo -e $"\e[91mError:\e[0m Invalid destination! Check $forwarddef"
						echo -e $"\e[91mError:\e[0m Missing task destination definition at $jsonFile"
						exit 0
					fi
					
					#[ $loglevel -ge 1 ] && echo "forwarding media to user's $destination"

					json_cache_key_path="$jsonFile"
					
				elif [[ $destination == *"tasks/"* ]] ; then
				
					jsonFile="custom_nodes/comfyui_stereoscopic/config/""$destination"".json"
					if [ ! -e "$jsonFile" ] ; then
						echo -e $"\e[91mError:\e[0m Invalid destination! Check $forwarddef"
						echo -e $"\e[91mError:\e[0m Missing task destination definition at $jsonFile"
						exit 0
					fi

					#[ $loglevel -ge 1 ] && echo "forwarding media to $destination"
					
					json_cache_key_path="$jsonFile"
					
				else
					jsonFile="custom_nodes/comfyui_stereoscopic/config/stages/""$destination"".json"
					if [ ! -e  "$jsonFile" ] ; then
						echo -e $"\e[91mError:\e[0m Invalid destination! Check $forwarddef"
						echo -e $"\e[91mError:\e[0m Missing stage destination definition at $jsonFile"
						exit 0
					fi
					
					#[ $loglevel -ge 1 ] && echo "forwarding media to stage $destination"
					
					json_cache_key_path="$jsonFile"
					
				fi
				load_json_rule_cache "$json_cache_key_path" "$json_cache_key_path" || exit 1
				inputrule="${FORWARD_INPUT_RULE_CACHE[$json_cache_key_path]}"
				
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
									if should_skip_old_forward_file "$file" ; then
										continue
									fi
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
									if should_skip_old_forward_file "$file" ; then
										continue
									fi
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
											if should_skip_old_forward_file "$file" ; then
												continue
											fi
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
		if ! has_forward_media_candidates "$FORWARD_SOURCE_DIR" ; then
			forward_last_run_write "$sourcestage" "$(date +%s)"
		fi
	else
		[ $loglevel -ge 2 ] &&  echo -e $"\e[2m""     no forward.txt file\e[0m"
	fi
fi

exit 0

