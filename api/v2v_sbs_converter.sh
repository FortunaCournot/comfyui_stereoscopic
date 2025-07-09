#!/bin/sh
#
# v2v_sbs_converter.sh
#
# Creates SBS video from a base video (input)
# Copyright (c) 2025 FortunaCournot. MIT License.

# ComfyUI API script needs the following custom node packages: 
#  comfyui_stereoscopic, comfyui_fearnworksnodes

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).
# Prerequisite: Configured path variables below.
# Prerequisite: Git Bash installed. Call this script in Git Bash

# - It will split the input video into segements,
# - It queues sbs conversion workflows via api,
# - Creates a shell script for concating resulting sbs segments
# - Wait until comfyui is done, then call created script manually.

# set FFMPEGPATH if ffmpeg binary is not in your enviroment path
FFMPEGPATH=
# either start this script in ComfyUI folder or enter absolute path of ComfyUI folder in your ComfyUI_windows_portable here
COMFYUIPATH=.
# API relative to COMFYUIPATH, or absolute path:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/v2v_sbs_converter.py

if test $# -ne 3
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 depth_scale depth_offset input"
    echo "E.g.: $0 1.0 0.0 SmallIconicTown.mp4"
else
	cd $COMFYUIPATH

	depth_scale="$1"
	shift
	depth_offset="$1"
	shift
	INPUT="$1"
	shift
	
	TARGETPREFIX=${INPUT##*/}
	TARGETPREFIX=output/sbs/${TARGETPREFIX%.mp4}
	mkdir -p "$TARGETPREFIX"".tmpseg"
	mkdir -p "$TARGETPREFIX"".tmpsbs"
	SEGDIR=`realpath "$TARGETPREFIX"".tmpseg"`
	SBSDIR=`realpath "$TARGETPREFIX"".tmpsbs"`
	touch $TARGETPREFIX
	TARGETPREFIX=`realpath "$TARGETPREFIX"`
	echo "prompting for $TARGETPREFIX"
	rm "$TARGETPREFIX"
	
	nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -i "$INPUT" -c:v libx264 -crf 22 -map 0 -segment_time 1 -g 9 -sc_threshold 0 -force_key_frames "expr:gte(t,n_forced*9)" -f segment "$SEGDIR/segment%05d.mp4"
	for f in "$SEGDIR"/*.mp4 ; do
		TESTAUDIO=`ffprobe -i "$f" -show_streams -select_streams a -loglevel error`
		if [[ ! $TESTAUDIO =~ "[STREAM]" ]]; then
			mv "$f" "${f%.mp4}_na.mp4"
			nice ffmpeg -hide_banner -loglevel error -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 -i "${f%.mp4}_na.mp4" -y -f ffmetadata metadata.txt -c:v copy -c:a aac -shortest "$f"
		fi
		../python_embeded/python.exe $SCRIPTPATH $depth_scale $depth_offset $targetprefix "$f" "$SBSDIR"/sbssegment
	done
	
	
	
	echo "#!/bin/sh" >"$SBSDIR/concat.sh"
	echo "cd \"\$(dirname \"\$0\")\"" >>"$SBSDIR/concat.sh"
	echo "rm -rf \"$TARGETPREFIX\"\".tmpseg\"" >>"$SBSDIR/concat.sh"
	echo "if [ -e ./sbssegment_00001-audio.mp4 ]" >>"$SBSDIR/concat.sh"
	echo "then" >>"$SBSDIR/concat.sh"
	echo "    list=\`find . -type f -print | grep mp4 | grep -v audio\`" >>"$SBSDIR/concat.sh"
	echo "    rm \$list" >>"$SBSDIR/concat.sh"
	echo "fi" >>"$SBSDIR/concat.sh"
	echo "for f in ./*.mp4 ; do" >>"$SBSDIR/concat.sh"
	echo "	echo \"file \$f\" >> "$SBSDIR"/list.txt" >>"$SBSDIR/concat.sh"
	echo "done" >>"$SBSDIR/concat.sh"
	echo "nice "$FFMPEGPATH"ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i list.txt -c copy $TARGETPREFIX"".mp4" >>"$SBSDIR/concat.sh"
	echo "cd .." >>"$SBSDIR/concat.sh"
	echo "rm -rf \"$TARGETPREFIX\"\".tmpsbs\"" >>"$SBSDIR/concat.sh"
	echo " "
	echo "Wait until comfyui tasks are done (check ComfyUI queue in browser), then call the script manually: $SBSDIR/concat.sh"
fi

