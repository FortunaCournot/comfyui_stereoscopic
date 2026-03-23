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

render_progress_bar() {
    local current="$1"
    local total="$2"
    local label="$3"
    local width=24
    local filled empty percent filled_bar empty_bar

    [ "${loglevel:-0}" -ge 0 ] || return 0
    [ -t 1 ] || return 0
    [ "$total" -le 0 ] && total=1

    filled=$((current * width / total))
    empty=$((width - filled))
    percent=$((current * 100 / total))
    filled_bar=$(printf '%*s' "$filled" '')
    empty_bar=$(printf '%*s' "$empty" '')
    filled_bar=${filled_bar// /#}
    empty_bar=${empty_bar// /-}

    printf '\r\e[2K\e[2m[%s%s] %3d%% (%d/%d) %s\e[0m' "$filled_bar" "$empty_bar" "$percent" "$current" "$total" "$label"
    if [ "$current" -ge "$total" ] ; then
        printf '\n'
    fi
}

count_non_empty_lines() {
    printf '%s\n' "$1" | awk 'NF { count++ } END { print count + 0 }'
}

list_active_task_dirs() {
    if [ -f "$FS_STATUS_FILE" ]; then
        awk -F'=' '/^any\|output\/vr\/tasks\/[^/]+=/{ if (($2 + 0) > 1) { key=$1; sub(/^any\|output\/vr\/tasks\//, "", key); print key } }' "$FS_STATUS_FILE"
        return
    fi

    find output/vr/tasks -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null
}

do_autoforward() {
    echo -e $"\e[2mSearching for files left to forward and cleanup.\e[0m"
    FS_STATUS_FILE="${FS_STATUS_FILE:-user/default/comfyui_stereoscopic/.fs_status.properties}"

    get_status_count() {
        typ="$1"; shift || true
        dir="$1"
            case "$typ" in
                any)
                    count_files_any_ext "$dir"
                    ;;
                images)
                    count_files_with_exts "$dir" png jpg jpeg webp
                    ;;
                videos)
                    count_files_with_exts "$dir" mp4 webm ts mkv avi mov
                    ;;
                audio)
                    count_files_with_exts "$dir" flac mp3 wav aac m4a
                    ;;
                *)
                    echo 0
                    ;;
            esac
    }
    STAGE_TOTAL=11
    TASKDIR=$(list_active_task_dirs)
    TASK_TOTAL=$(count_non_empty_lines "$TASKDIR")
    TOTAL_ITEMS=$((STAGE_TOTAL + TASK_TOTAL))
    CURRENT_ITEM=0
    for stagepath in scaling slides fullsbs singleloop slideshow concat dubbing/sfx watermark/encrypt watermark/decrypt caption interpolate ; do
        CURRENT_ITEM=$((CURRENT_ITEM + 1))
        render_progress_bar "$CURRENT_ITEM" "$TOTAL_ITEMS" "Forward/cleanup: $stagepath"
        [ "${loglevel:-0}" -ge 1 ] && echo " - $stagepath"
        FILECOUNT=$(get_status_count any "output/vr/$stagepath")
        # forward.txt + one media
        if [ "$FILECOUNT" -gt 1 ] ; then
            ./custom_nodes/comfyui_stereoscopic/api/forward.sh $stagepath || exit 1
        fi
    done

    for task in $TASKDIR; do
        if [ -n "$task" ] ; then
			CURRENT_ITEM=$((CURRENT_ITEM + 1))
            render_progress_bar "$CURRENT_ITEM" "$TOTAL_ITEMS" "Forward/cleanup: tasks/$task"
            [ "${loglevel:-0}" -ge 1 ] && echo " - tasks/$task"
            ./custom_nodes/comfyui_stereoscopic/api/forward.sh tasks/$task || exit 1
        fi
    done

    rm -rf -- \
        output/vr/scaling/intermediate input/vr/scaling/intermediate \
        output/vr/slides/intermediate input/vr/slides/intermediate \
        output/vr/fullsbs/intermediate input/vr/fullsbs/intermediate \
        output/vr/singleloop/intermediate input/vr/singleloop/intermediate \
        output/vr/slideshow/intermediate input/vr/slideshow/intermediate \
        output/vr/concat/intermediate input/vr/concat/intermediate \
        output/vr/dubbing/sfx/intermediate input/vr/dubbing/sfx/intermediate \
        output/vr/watermark/encrypt/intermediate input/vr/watermark/encrypt/intermediate \
        output/vr/watermark/decrypt/intermediate input/vr/watermark/decrypt/intermediate \
        output/vr/caption/intermediate input/vr/caption/intermediate \
        output/vr/interpolate/intermediate input/vr/interpolate/intermediate \
        output/vr/tasks/intermediate output/vr/tasks/*/intermediate 2>/dev/null
}

return 0
