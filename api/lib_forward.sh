#!/bin/sh
# Library: forward helpers
# Provides: do_autoforward
# Use `lib_fs.sh` helper for baseline counting so implementation is centralized
if [ -z "$COMFYUIPATH" ]; then
    echo "Error: COMFYUIPATH not set in lib_forward.sh (cwd=$(pwd)). Start script from repository root."; return 1;
fi
LIB_FS="$COMFYUIPATH/custom_nodes/comfyui_stereoscopic/api/lib_fs.sh"
if [ -f "$LIB_FS" ]; then
    . "$LIB_FS" || { echo "Error: failed to source canonical $LIB_FS in lib_forward.sh (cwd=$(pwd))"; return 1; }
else
    echo "Error: required lib_fs not found at canonical path: $LIB_FS"; return 1;
fi

do_autoforward() {
    echo -e $"\e[2mSearching for files left to forward and cleanup.\e[0m"
    for stagepath in scaling slides fullsbs singleloop slideshow concat dubbing/sfx watermark/encrypt watermark/decrypt caption interpolate ; do
        [ "${loglevel:-0}" -ge 1 ] && echo " - $stagepath"
        FILECOUNT=$(count_files_any_ext "output/vr/$stagepath")
        # forward.txt + one media
        if [ "$FILECOUNT" -gt 1 ] ; then
            ./custom_nodes/comfyui_stereoscopic/api/forward.sh $stagepath || exit 1
        fi
        rm -rf -- output/vr/$stagepath/intermediate input/vr/$stagepath/intermediate 2>/dev/null
    done

    TASKDIR=`find output/vr/tasks -maxdepth 1 -type d`
    for task in $TASKDIR; do
        task=${task#output/vr/tasks/}
        if [ -n "$task" ] ; then
            [ "${loglevel:-0}" -ge 1 ] && echo " - tasks/$task"
            FILECOUNT=$(count_files_any_ext "output/vr/tasks/$task")
            # forward.txt + one media
            if [ "$FILECOUNT" -gt 1 ] ; then
                ./custom_nodes/comfyui_stereoscopic/api/forward.sh tasks/$task || exit 1
            fi
            rm -rf -- output/vr/tasks/intermediate output/vr/tasks/$task/intermediate 2>/dev/null
        fi
    done
}

return 0
