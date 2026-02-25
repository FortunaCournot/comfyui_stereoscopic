#!/bin/sh
# Library: forward helpers
# Provides: do_initial_autoforward

do_autoforward() {
    echo -e $"\e[2mSearching for files left to forward and cleanup.\e[0m"
    for stagepath in scaling slides fullsbs singleloop slideshow concat dubbing/sfx watermark/encrypt watermark/decrypt caption interpolate ; do
        [ $loglevel -ge 1 ] && echo " - $stagepath"
        FILECOUNT=`find output/vr/$stagepath -maxdepth 1 -type f -name '*.*' | wc -l 2>/dev/null`
        # forward.txt + one media
        if [ $FILECOUNT -gt 1 ] ; then
            ./custom_nodes/comfyui_stereoscopic/api/forward.sh $stagepath || exit 1
        fi
        rm -rf -- output/vr/$stagepath/intermediate input/vr/$stagepath/intermediate 2>/dev/null
    done

    TASKDIR=`find output/vr/tasks -maxdepth 1 -type d`
    for task in $TASKDIR; do
        task=${task#output/vr/tasks/}
        if [ ! -z $task ] ; then
            [ $loglevel -ge 1 ] && echo " - tasks/$task"
            FILECOUNT=`find output/vr/tasks/$task -maxdepth 1 -type f -name '*.*' | wc -l 2>/dev/null`
            # forward.txt + one media
            if [ $FILECOUNT -gt 1 ] ; then
                ./custom_nodes/comfyui_stereoscopic/api/forward.sh tasks/$task || exit 1
            fi
            rm -rf -- output/vr/tasks/intermediate output/vr/tasks/$task/intermediate 2>/dev/null
        fi
    done
}

return 0
