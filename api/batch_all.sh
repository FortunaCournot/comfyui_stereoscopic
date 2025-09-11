#!/bin/sh
# Executes the whole SBS workbench pipeline
# Copyright (c) 2025 Fortuna Cournot. MIT License.

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).
# Prerequisite: Placed sbs_api.py somewhere and configured path variables below.


# abolute path of ComfyUI folder in your ComfyUI_windows_portable
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`

cd $COMFYUIPATH

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

export CONFIGFILE
if [ -e $CONFIGFILE ] ; then
	loglevel=$(awk -F "=" '/loglevel=/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
	[ $loglevel -ge 2 ] && set -x
    config_version=$(awk -F "=" '/config_version=/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
	PIPELINE_AUTOFORWARD=$(awk -F "=" '/PIPELINE_AUTOFORWARD=/ {print $2}' $CONFIGFILE) ; PIPELINE_AUTOFORWARD=${PIPELINE_AUTOFORWARD:-1}
	COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST=/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
	COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT=/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
	export COMFYUIHOST COMFYUIPORT
else
    touch "$CONFIGFILE"
fi

onExit() {
	exit_code=$?
	[ $loglevel -ge 1 ] && echo "Exit code: $exit_code"
	exit $exit_code
}
trap onExit EXIT

FREESPACE=$(df -khBG . | tail -n1 | awk '{print $4}')
FREESPACE=${FREESPACE%G}
MINSPACE=10
status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
if test $# -ne 0
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 "
    echo "E.g.: $0 "
elif [ "$status" = "closed" ]; then
	echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on port 8188"
elif [[ $FREESPACE -lt $MINSPACE ]] ; then
	echo -e $"\e[91mError:\e[0m Less than $MINSPACE""G left on device: $FREESPACE""G"
	./custom_nodes/comfyui_stereoscopic/api/clear.sh || exit 1
	FREESPACE=$(df -khBG . | tail -n1 | awk '{print $4}')
	FREESPACE=${FREESPACE%G}
	if [[ $FREESPACE -lt $MINSPACE ]] ; then
		exit 1
	fi
elif [ -d "custom_nodes" ]; then

	### CHECK FOR OPTIONAL NODE PACKAGES ###
	DUBBING_DEP_ERROR=
	if [ ! -d custom_nodes/comfyui-florence2 ]; then
		echo -e $"\e[91mError:\e[0m Custom nodes ComfyUI-Florence2 could not be found."
		DUBBING_DEP_ERROR="x"
	fi
	if [ ! -d custom_nodes/comfyui-mmaudio ] ; then
		echo -e $"\e[91mError:\e[0m Custom nodes ComfyUI-MMAudio could not be found."
		DUBBING_DEP_ERROR="x"
	fi
	
	# LOCAL: prepare move output to next stage input (This should happen in daemon, too)
	mkdir -p input/vr/scaling input/vr/fullsbs

	# workaround for recovery problem.
	#./custom_nodes/comfyui_stereoscopic/api/clear.sh || exit 1

	
	SCALECOUNT=`find input/vr/scaling -maxdepth 1 -type f -name '*.mp4' -o -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' -o -name '*.webm' -o -name '*.webp' | wc -l`
	OVERRIDECOUNT=`find input/vr/scaling/override -maxdepth 1 -type f -name '*.mp4' -o -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' -o -name '*.webm' -o -name '*.webp' | wc -l`
	if [ $SCALECOUNT -ge 1 ] || [ $OVERRIDECOUNT -ge 1 ]; then
		MEMFREE=`awk '/MemFree/ { printf "%.0f \n", $2/1024/1024 }' /proc/meminfo`
		MEMTOTAL=`awk '/MemTotal/ { printf "%.0f \n", $2/1024/1024 }' /proc/meminfo`
		if [ $MEMFREE -ge 16 ] ; then
			# UPSCALING: Video -> Video. Limited to 60s and 4K.
			# In:  input/vr/scaling
			# Out: output/vr/scaling
			[ $loglevel -ge 1 ] && echo "**************************"
			[ $loglevel -ge 0 ] && echo "******** SCALING *********"
			[ $loglevel -ge 1 ] && echo "**************************"
			if [ $SCALECOUNT -ge 1 ]; then
				./custom_nodes/comfyui_stereoscopic/api/batch_scaling.sh || exit 1
			fi
			if [ $OVERRIDECOUNT -ge 1 ]; then
				./custom_nodes/comfyui_stereoscopic/api/batch_scaling.sh /override || exit 1
			fi
			rm -f user/default/comfyui_stereoscopic/.daemonstatus
		else
			echo -e $"\e[93mWarning:\e[0m Less than 16GB of free memory - Skipped scaling. Memory: $MEMFREE/ $MEMTOTAL"
			mv -- input/vr/scaling/*.* output/vr/scaling
		fi
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh scaling || exit 1 )
	fi


	SLIDECOUNT=`find input/vr/slides -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' -o -name '*.webm' -o -name '*.webp' | wc -l`
	if [ $SLIDECOUNT -ge 2 ]; then
		# PREPARE 4K SLIDES
		# In:  input/vr/slides
		# Out: output/slides
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "***** PREPARE SLIDES *****"
		[ $loglevel -ge 1 ] && echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_prepare_slides.sh || exit 1
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh slides || exit 1 )
	fi
	
	
	
	SBSCOUNT=`find input/vr/fullsbs -maxdepth 1 -type f -name '*.mp4' -o -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' -o -name '*.webm' -o -name '*.webp' | wc -l`
	if [ $SBSCOUNT -ge 1 ]; then
		# SBS CONVERTER: Video -> Video, Image -> Image
		# In:  input/vr/fullsbs
		# Out: output/sbs
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "*****  SBSCONVERTING *****"
		[ $loglevel -ge 1 ] && echo "**************************"
		SBS_DEPTH_SCALE=$(awk -F "=" '/SBS_DEPTH_SCALE=/ {print $2}' $CONFIGFILE) ; SBS_DEPTH_SCALE=${SBS_DEPTH_SCALE:-"1.25"}
		SBS_DEPTH_OFFSET=$(awk -F "=" '/SBS_DEPTH_OFFSET=/ {print $2}' $CONFIGFILE) ; SBS_DEPTH_OFFSET=${SBS_DEPTH_OFFSET:-"0.0"}
		./custom_nodes/comfyui_stereoscopic/api/batch_sbsconverter.sh $SBS_DEPTH_SCALE $SBS_DEPTH_OFFSET
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh fullsbs || exit 1 )
	fi


	SINGLELOOPCOUNT=`find input/vr/singleloop -maxdepth 1 -type f -name '*.mp4' -o  -name '*.webm' | wc -l`
	if [ $SINGLELOOPCOUNT -ge 1 ]; then
		# SINGLE LOOP
		# In:  input/vr/singleloop_in
		# Out: output/vr/singleloop
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "****** SINGLE LOOP *******"
		[ $loglevel -ge 1 ] && echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_singleloop.sh || exit 1
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh singleloop || exit 1 )
	fi

	
	SLIDESBSCOUNT=`find input/vr/slideshow -maxdepth 1 -type f -name '*.png' | wc -l`
	if [ $SLIDESBSCOUNT -ge 2 ]; then
		# MAKE SLIDESHOW
		# In:  input/vr/slideshow
		# Out: output/vr/slideshow
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "***** MAKE SLIDESHOW *****"
		[ $loglevel -ge 1 ] && echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_make_slideshow.sh || exit 1
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh slideshow || exit 1 )
	fi


	CONCATCOUNT=`find input/vr/concat -maxdepth 1 -type f -name '*.mp4' | wc -l`
	if [ $CONCATCOUNT -ge 1 ]; then
		# CONCAT
		# In:  input/vr/concat_in
		# Out: output/vr/concat
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "******** CONCAT **********"
		[ $loglevel -ge 1 ] && echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_concat.sh || exit 1
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh concat || exit 1 )
	fi

	### SKIP IF DEPENDENCY CHECK FAILED ###
	DUBCOUNTSFX=`find input/vr/dubbing/sfx -maxdepth 1 -type f -name '*.mp4' -o  -name '*.webm'  | wc -l`
	if [[ -z $DUBBING_DEP_ERROR ]] && [ $DUBCOUNTSFX -gt 0 ]; then
		if [ -x "$(command -v nvidia-smi)" ]; then
			# DUBBING: Video -> Video with SFX
			# In:  input/vr/dubbing/sfx
			# Out: output/vr/dubbing/sfx
			[ $loglevel -ge 1 ] && echo "**************************"
			[ $loglevel -ge 0 ] && echo "****** DUBBING SFX *******"
			[ $loglevel -ge 1 ] && echo "**************************"
			./custom_nodes/comfyui_stereoscopic/api/batch_dubbing_sfx.sh || exit 1
			rm -f user/default/comfyui_stereoscopic/.daemonstatus
			[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh dubbing/sfx || exit 1 )
		else
			echo 'Warning: nvidea-smi is not installed. Dubbing required CUDA.'
		fi

	elif [ $DUBCOUNTSFX -gt 0 ]; then
		mkdir -p input/vr/dubbing/sfx/error
		mv -fv input/vr/dubbing/sfx/*.mp4 input/vr/dubbing/sfx/error
	fi

	### SKIP IF CONFIG CHECK FAILED ###
	WMECOUNT=`find input/vr/watermark/encrypt -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
	WMDCOUNT=`find input/vr/watermark/decrypt -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
	if [ $WMECOUNT -gt 0 ] ; then
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "****** ENCRYPTING ********"
		[ $loglevel -ge 1 ] && echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_watermark_encrypt.sh || exit 1
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh watermark/encrypt || exit 1 )
	fi
	if [ $WMDCOUNT -gt 0 ] ; then
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "****** DECRYPTING ********"
		[ $loglevel -ge 1 ] && echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_watermark_decrypt.sh || exit 1
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
	fi

	### SKIP IF CONFIG CHECK FAILED ###
	CAPCOUNT=`find input/vr/caption -maxdepth 1 -type f -name '*.mp4' -o  -name '*.webm'  -o -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.webp' | wc -l`
	if [ $CAPCOUNT -gt 0 ] ; then
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "******** CAPTION *********"
		[ $loglevel -ge 1 ] && echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_caption.sh || exit 1
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh caption || exit 1 )
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
	fi

	INTERPOLATECOUNT=`find input/vr/interpolate -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' | wc -l`
	if [ $INTERPOLATECOUNT -gt 0 ] ; then
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "****** INTERPOLATE *******"
		[ $loglevel -ge 1 ] && echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_interpolate.sh || exit 1
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh interpolate || exit 1 )
	fi

	TASKCOUNT=`find input/vr/tasks/*/ -maxdepth 1 -type f | wc -l`
	if [ $TASKCOUNT -gt 0 ] ; then
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "********* TASKS **********"
		[ $loglevel -ge 1 ] && echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_tasks.sh || exit 1
		rm -f user/default/comfyui_stereoscopic/.daemonstatus
		
		TASKDIR=`find output/vr/tasks -maxdepth 1 -type d`
		for task in $TASKDIR; do
			task=${task#output/vr/tasks/}
			if [ ! -z $task ] ; then
				[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh tasks/$task || exit 1 )
			fi
		done

	fi
	
	[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh check/judge || exit 1 )

	done

else
	  echo -e $"\e[91mError:\e[0m Wrong path to script. COMFYUIPATH=$COMFYUIPATH"
fi
exit 0

