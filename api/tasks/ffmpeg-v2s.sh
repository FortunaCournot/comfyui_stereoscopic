#!/bin/sh
#
# ffmpeg-v2s.sh
#
# extracts/encodes audio from a video input using ffmpeg and places result
# into output/vr/tasks/<taskname>. Designed as companion to ffmpeg-v2v.sh.
#
# Default audio format: AAC in .m4a container (good quality/size/compatibility).
# Options are taken from the blueprint JSON like in ffmpeg-v2v.sh and should
# contain ffmpeg audio-specific flags (e.g. -c:a aac -b:a 192k -vn ...).
#
# Prerequisite: ComfyUI repo layout, Git Bash. Call from Git Bash.

if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi

assertlimit() {
    mode_upperlimit=$1
    kv=$2
    
    key=${kv%=*}
    value2=$(( ${kv#*=} ))

    temp=`grep "$key" output/vr/tasks/intermediate/probe.txt`
    temp=${temp#*:}
    temp="${temp%,*}"
    temp="${temp%\"*}"
    temp="${temp#*\"}"
    value1=$(( $temp ))

    if [ "$mode_upperlimit" != "true" ] ; then tmp="$value1" ; value1="$value2" ; value2="$tmp" ; fi
    
    if [ "$value1" -gt "$value2" ] ; then
        echo -e $"\e[32mLimit already fullfilled:\e[0m $key": $value1 > $value2"". Skip processing and forwarding to output."
        mv -vf -- "$INPUT" "$FINALTARGETFOLDER"
        exit 0
    else
        echo "Condition met. $key": $value1 <= $value2"
    fi
}

COMFYUIPATH=`realpath $(dirname "$0")/../../../..`

if test $# -ne 3 
then
    echo "Usage: $0 jsonblueprintpath taskname inputfile"
else
    
    cd $COMFYUIPATH

    CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

    NOLINE=-ne
    
    export CONFIGFILE
    if [ -e $CONFIGFILE ] ; then
        loglevel=$(awk -F "=" '/loglevel=/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
        [ $loglevel -ge 2 ] && set -x
        [ $loglevel -ge 2 ] && NOLINE="" ; echo $NOLINE
        config_version=$(awk -F "=" '/config_version=/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
    else
        echo -e $"\e[91mError:\e[0m No config!?"
        exit 1
    fi

    FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX=/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}

    EXIFTOOLBINARY=$(awk -F "=" '/EXIFTOOLBINARY=/ {print $2}' $CONFIGFILE) ; EXIFTOOLBINARY=${EXIFTOOLBINARY:-""}

    PYTHON_BIN_PATH=
    if [ -d "../python_embeded" ]; then
      PYTHON_BIN_PATH=../python_embeded/
    fi

    BLUEPRINTCONFIG="$1"
    shift
    TASKNAME="$1"
    shift
    INPUT="$1"
    shift

    PROGRESS=" "
    if [ -e input/vr/tasks/BATCHPROGRESS.TXT ]
    then
        PROGRESS=`cat input/vr/tasks/BATCHPROGRESS.TXT`" "
    fi
    regex="[^/]*$"
    echo "========== $PROGRESS"`echo $INPUT | grep -oP "$regex"`" =========="
    
    mkdir -p output/vr/tasks/intermediate

    `"$FFMPEGPATHPREFIX"ffprobe -hide_banner -v error -select_streams V:0 -show_entries stream=bit_rate,width,height,r_frame_rate,duration,nb_frames -of json -i "$INPUT" >output/vr/tasks/intermediate/probe.txt`
    `"$FFMPEGPATHPREFIX"ffprobe -hide_banner -v error -select_streams a:0 -show_entries stream=codec_type -of json -i "$INPUT" >>output/vr/tasks/intermediate/probe.txt`

    TARGETPREFIX=${INPUT##*/}
    INPUT=`realpath "$INPUT"`
    TARGETPREFIX=output/vr/tasks/intermediate/${TARGETPREFIX%.*}
    FINALTARGETFOLDER=`realpath "output/vr/tasks/$TASKNAME"`
    mkdir -p $FINALTARGETFOLDER

    upperlimits=`cat "$BLUEPRINTCONFIG" | grep -o '"upperlimits":[^\"]*"[^\"]*"' | sed -E 's/".*".*"(.*)"/\1/'`
    for parameterkv in $(echo $upperlimits | sed "s/,/ /g")
    do
        assertlimit "true" "$parameterkv"
    done
    
    lowerlimits=`cat "$BLUEPRINTCONFIG" | grep -o '"lowerlimits":[^\"]*"[^\"]*"' | sed -E 's/".*".*"(.*)"/\1/'`
    for parameterkv in $(echo $lowerlimits | sed "s/,/ /g")
    do
        assertlimit "false" "$parameterkv"
    done

    options=`cat "$BLUEPRINTCONFIG" | grep -o '"options":[^\"]*"[^\"]*"' | sed -E 's/".*".*"(.*)"/\1/'`
    options="${options//\'/}"
    options="${options//\$INPUT/"$INPUT"}"

    # Default to AAC in M4A container if blueprint doesn't specify extension
    EXTENSION=`cat "$BLUEPRINTCONFIG" | grep -o '"extension":[^\"]*"[^\"]*"' | sed -E 's/".*".*"(.*)"/\1/'`
    if [ -z "$EXTENSION" ] ; then
        EXTENSION=".m4a"
    fi

    [ $loglevel -lt 2 ] && set -x
    # Extract/encode audio only (-vn) and apply provided audio options
    nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -stats -y -i "$INPUT" -vn $options "$TARGETPREFIX""$EXTENSION"
    set +x && [ $loglevel -ge 2 ] && set -x

    if [ -e "$TARGETPREFIX""$EXTENSION" ] && [ -s "$TARGETPREFIX""$EXTENSION" ] ; then
        # try to copy tags from source container when possible
        [ -e "$EXIFTOOLBINARY" ] && "$EXIFTOOLBINARY" -all= -tagsfromfile "$INPUT" -all:all -overwrite_original "$TARGETPREFIX""$EXTENSION" && echo "tags copied."
        mv -- "$TARGETPREFIX""$EXTENSION" $FINALTARGETFOLDER
        mkdir -p input/vr/tasks/$TASKNAME/done
        mv -- $INPUT input/vr/tasks/$TASKNAME/done
        echo -e $"\e[92mtask done.\e[0m"
    else
        echo -e $"\e[91mError:\e[0m Task failed. $TARGETPREFIX""$EXTENSION missing or zero-length."
        rm -f -- "$TARGETPREFIX""$EXTENSION" 2>/dev/null
        mkdir -p input/vr/tasks/$TASKNAME/error
        mv -- $INPUT input/vr/tasks/$TASKNAME/error
    fi

fi
exit 0
