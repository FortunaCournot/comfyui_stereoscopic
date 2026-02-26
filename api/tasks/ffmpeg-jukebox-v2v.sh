#!/bin/sh
#
# ffmpeg-jukebox-v2v.sh
#
# Variant of ffmpeg-v2v.sh that replaces the audio track with a random
# audio file picked from a jukebox directory (relative to the ComfyUI repo).
# - `jukeboxpath` is a required blueprint parameter (relative path).
# - `mixaudio` optional blueprint parameter; when "true" will mix the
#    jukebox audio with the existing audio. Otherwise existing audio is discarded.
# - `options` in the blueprint is NOT allowed for this task; presence will error.
# - Static encoding options are hardcoded in this script.
#
# Call: ffmpeg-jukebox-v2v.sh <blueprint.json> <taskname> <inputfile>

if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi

COMFYUIPATH=`realpath $(dirname "$0")/../../../..`

STATIC_OPTIONS="-c:v libx264 -preset fast -crf 23 -c:a aac -b:a 192k"

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

if test $# -ne 3 
then
    echo "Usage: $0 jsonblueprintpath taskname inputfile"
    exit 1
else
    cd $COMFYUIPATH

    CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini
    export CONFIGFILE
    if [ -e $CONFIGFILE ] ; then
        loglevel=$(awk -F "=" '/loglevel=/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
        [ $loglevel -ge 2 ] && set -x
    else
        echo -e $"\e[91mError:\e[0m No config!?"
        exit 1
    fi

    FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX=/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}

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

    # If blueprint defines options, this task must fail (static options only)
    options=`cat "$BLUEPRINTCONFIG" | grep -o '"options":[^\"]*"[^\"]*"' | sed -E 's/".*".*"(.*)"/\1/'`
    options="${options//\'\/}"
    if [ -n "$options" ] ; then
        echo -e $"\e[91mError:\e[0m This task does not accept blueprint 'options'. Remove it from $BLUEPRINTCONFIG and retry."
        exit 2
    fi

    # Required jukeboxpath parameter (relative to COMFYUIPATH)
    jukeboxpath=`cat "$BLUEPRINTCONFIG" | grep -o '"jukeboxpath":[^,}]*' | sed -E 's/.*:[[:space:]]*"?([^"} ]*)"?.*/\1/'`
    jukeboxpath=`echo "$jukeboxpath" | sed -e 's/\r//g' -e 's/^ *//g' -e 's/ *$//g'`
    if [ -z "$jukeboxpath" ] ; then
        echo -e $"\e[91mError:\e[0m Missing required blueprint parameter 'jukeboxpath'."
        exit 3
    fi

    # mixaudio optional boolean (accepts true/false or "true"/"false")
    mixaudio_raw=`cat "$BLUEPRINTCONFIG" | grep -o '"mixaudio":[^,}]*' | sed -E 's/.*:[[:space:]]*"?([^"} ]*)"?.*/\1/'`
    mixaudio=`echo "$mixaudio_raw" | tr '[:upper:]' '[:lower:]' | sed -e 's/\r//g' -e 's/^ *//g' -e 's/ *$//g'`

    # Optional volume parameter for jukebox audio (integer percent). Default 100.
    volume_raw=`cat "$BLUEPRINTCONFIG" | grep -o '"volume"[[:space:]]*:[^,}]*' | sed -E 's/.*:[[:space:]]*"?([^"} ]*)"?.*/\1/'`
    volume=`echo "$volume_raw" | sed -e 's/\r//g' -e 's/^ *//g' -e 's/ *$//g'`
    if [ -z "$volume" ] ; then
        volume=100
    fi
    # compute ffmpeg multiplier
    VOL_MULT=""
    if printf '%s' "$volume" | grep -qE '^[0-9]+$' && [ "$volume" -ne 100 ] ; then
        VOL_MULT=$(awk -v v="$volume" 'BEGIN{printf "%.3f", v/100}')
    fi

    EXTENSION=`cat "$BLUEPRINTCONFIG" | grep -o '"extension":[^\"]*"[^\"]*"' | sed -E 's/".*".*"(.*)"/\1/'`
    if [ -z "$EXTENSION" ] ; then
        EXTENSION="."${INPUT##*.}
    fi

    [ $loglevel -ge 2 ] && set -x

    # locate jukebox directory and pick a random audio file
    JUKEBOXDIR="$COMFYUIPATH/$jukeboxpath"
    if [ ! -d "$JUKEBOXDIR" ] ; then
        echo -e $"\e[91mError:\e[0m jukeboxpath directory not found: $JUKEBOXDIR"
        exit 4
    fi

    AUDIOFILE=`find "$JUKEBOXDIR" -type f \( -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.aac' -o -iname '*.wav' -o -iname '*.ogg' -o -iname '*.flac' -o -iname '*.opus' \) -print | awk 'BEGIN{srand()} {a[NR]=$0} END{ if (NR>0) print a[int(rand()*NR)+1] }'`
    if [ -z "$AUDIOFILE" ] ; then
        echo -e $"\e[91mError:\e[0m No audio files found in jukeboxpath: $JUKEBOXDIR"
        exit 5
    fi

    echo "Using jukebox audio: $AUDIOFILE"

    # detect whether original input has an audio stream
    has_audio=0
    if grep -q '"codec_type": *"audio"' output/vr/tasks/intermediate/probe.txt 2>/dev/null ; then
        has_audio=1
    fi

    # Build and run ffmpeg command depending on mixaudio
    if [ "$mixaudio" = "true" ] && [ "$has_audio" -eq 1 ] ; then
        # mix original audio and jukebox audio; cut output to shortest input (usually video)
        if [ -n "$VOL_MULT" ] ; then
            # apply volume to jukebox input before mixing
            nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -stats -y -i "$INPUT" -i "$AUDIOFILE" -filter_complex "[1:a]volume=$VOL_MULT[b];[0:a][b]amix=inputs=2:duration=longest:dropout_transition=0[aout]" -map 0:v -map "[aout]" $STATIC_OPTIONS -shortest "$TARGETPREFIX""$EXTENSION"
        else
            nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -stats -y -i "$INPUT" -i "$AUDIOFILE" -filter_complex "[0:a][1:a]amix=inputs=2:duration=longest:dropout_transition=0[aout]" -map 0:v -map "[aout]" $STATIC_OPTIONS -shortest "$TARGETPREFIX""$EXTENSION"
        fi
    else
        # discard original audio (unless it didn't exist), use jukebox audio as sole audio track
        if [ -n "$VOL_MULT" ] ; then
            nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -stats -y -i "$INPUT" -i "$AUDIOFILE" -map 0:v -map 1:a -af "volume=$VOL_MULT" $STATIC_OPTIONS -shortest "$TARGETPREFIX""$EXTENSION"
        else
            nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -stats -y -i "$INPUT" -i "$AUDIOFILE" -map 0:v -map 1:a $STATIC_OPTIONS -shortest "$TARGETPREFIX""$EXTENSION"
        fi
    fi

    set +x && [ $loglevel -ge 2 ] && set -x

    if [ -e "$TARGETPREFIX""$EXTENSION" ] && [ -s "$TARGETPREFIX""$EXTENSION" ] ; then
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
