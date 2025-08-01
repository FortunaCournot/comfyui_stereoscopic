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
	loglevel=$(awk -F "=" '/loglevel/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
	[ $loglevel -ge 2 ] && set -x
    config_version=$(awk -F "=" '/config_version/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
	PIPELINE_AUTOFORWARD=$(awk -F "=" '/PIPELINE_AUTOFORWARD/ {print $2}' $CONFIGFILE) ; PIPELINE_AUTOFORWARD=${PIPELINE_AUTOFORWARD:-1}
	COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
	COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
	export COMFYUIHOST COMFYUIPORT
else
    touch "$CONFIGFILE"
fi

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
	./custom_nodes/comfyui_stereoscopic/api/clear.sh
	FREESPACE=$(df -khBG . | tail -n1 | awk '{print $4}')
	FREESPACE=${FREESPACE%G}
	if [[ $FREESPACE -lt $MINSPACE ]] ; then
		exit
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
	./custom_nodes/comfyui_stereoscopic/api/clear.sh
	

	SCALECOUNT=`find input/vr/scaling -maxdepth 1 -type f -name '*.mp4' -o -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' -o -name '*.webm' -o -name '*.WEBM' | wc -l`
	OVERRIDECOUNT=`find input/vr/scaling/override -maxdepth 1 -type f -name '*.mp4' -o -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' -o -name '*.webm' -o -name '*.WEBM' | wc -l`
	if [ $SCALECOUNT -ge 1 ] || [ $OVERRIDECOUNT -ge 1 ]; then
		# UPSCALING: Video -> Video. Limited to 60s and 4K.
		# In:  input/vr/scaling
		# Out: output/vr/scaling
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "******** SCALING *********"
		[ $loglevel -ge 1 ] && echo "**************************"
		if [ $SCALECOUNT -ge 1 ]; then
			./custom_nodes/comfyui_stereoscopic/api/batch_scaling.sh
		fi
		if [ $OVERRIDECOUNT -ge 1 ]; then
			./custom_nodes/comfyui_stereoscopic/api/batch_scaling.sh /override
		fi
	fi

	# scaling -> fullsbs
	GLOBIGNORE="*_SBS_LR*.mp4"
	[ $PIPELINE_AUTOFORWARD -ge 1 ] && mv -f output/vr/scaling/*.mp4 output/vr/scaling/*.png output/vr/scaling/*.jpg output/vr/scaling/*.jpeg output/vr/scaling/*.PNG output/vr/scaling/*.JPG output/vr/scaling/*.JPEG output/vr/scaling/*.webm output/vr/scaling/*.WEBM input/vr/fullsbs  >/dev/null 2>&1
	unset GLOBIGNORE		


	SLIDECOUNT=`find input/vr/slides -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' -o -name '*.webm' -o -name '*.WEBM' | wc -l`
	if [ $SLIDECOUNT -ge 2 ]; then
		# PREPARE 4K SLIDES
		# In:  input/vr/slides
		# Out: output/slides
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "***** PREPARE SLIDES *****"
		[ $loglevel -ge 1 ] && echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_prepare_slides.sh
	fi
	
	# slides -> fullsbs
	GLOBIGNORE="*_SBS_LR*.*"
	[ $PIPELINE_AUTOFORWARD -ge 1 ] && mv -f output/vr/slides/*.* input/vr/fullsbs  >/dev/null 2>&1
	unset GLOBIGNORE		
	
	
	SBSCOUNT=`find input/vr/fullsbs -maxdepth 1 -type f -name '*.mp4' -o -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' -o -name '*.webm' -o -name '*.WEBM' | wc -l`
	if [ $SBSCOUNT -ge 1 ]; then
		# SBS CONVERTER: Video -> Video, Image -> Image
		# In:  input/vr/fullsbs
		# Out: output/sbs
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "*****  SBSCONVERTING *****"
		[ $loglevel -ge 1 ] && echo "**************************"
		SBS_DEPTH_SCALE=$(awk -F "=" '/SBS_DEPTH_SCALE/ {print $2}' $CONFIGFILE) ; SBS_DEPTH_SCALE=${SBS_DEPTH_SCALE:-"1.25"}
		SBS_DEPTH_OFFSET=$(awk -F "=" '/SBS_DEPTH_OFFSET/ {print $2}' $CONFIGFILE) ; SBS_DEPTH_OFFSET=${SBS_DEPTH_OFFSET:-"0.0"}
		./custom_nodes/comfyui_stereoscopic/api/batch_sbsconverter.sh $SBS_DEPTH_SCALE $SBS_DEPTH_OFFSET
	fi


	SINGLELOOPCOUNT=`find input/vr/singleloop -maxdepth 1 -type f -name '*.mp4' | wc -l`
	if [ $SINGLELOOPCOUNT -ge 1 ]; then
		# SINGLE LOOP
		# In:  input/vr/singleloop_in
		# Out: output/vr/singleloop
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "****** SINGLE LOOP *******"
		[ $loglevel -ge 1 ] && echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_singleloop.sh
	fi

	
	SLIDESBSCOUNT=`find input/vr/slideshow -maxdepth 1 -type f -name '*.png' | wc -l`
	if [ $SLIDESBSCOUNT -ge 2 ]; then
		# MAKE SLIDESHOW
		# In:  input/vr/slideshow
		# Out: output/vr/slideshow
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "***** MAKE SLIDESHOW *****"
		[ $loglevel -ge 1 ] && echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_make_slideshow.sh
	fi


	CONCATCOUNT=`find input/vr/concat -maxdepth 1 -type f -name '*_SBS_LR*.mp4' | wc -l`
	if [ $CONCATCOUNT -ge 1 ]; then
		# CONCAT
		# In:  input/vr/concat_in
		# Out: output/vr/concat
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "******** CONCAT **********"
		[ $loglevel -ge 1 ] && echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_concat.sh
	fi

	### SKIP IF DEPENDENCY CHECK FAILED ###
	DUBCOUNTSFX=`find input/vr/dubbing/sfx -maxdepth 1 -type f -name '*.mp4' | wc -l`
	if [[ -z $DUBBING_DEP_ERROR ]] && [ $DUBCOUNTSFX -gt 0 ]; then
		# DUBBING: Video -> Video with SFX
		# In:  input/vr/dubbing/sfx
		# Out: output/vr/dubbing/sfx
		[ $loglevel -ge 1 ] && echo "**************************"
		[ $loglevel -ge 0 ] && echo "****** DUBBING SFX *******"
		[ $loglevel -ge 1 ] && echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_dubbing_sfx.sh
	elif [ $DUBCOUNTSFX -gt 0 ]; then
		mkdir -p input/vr/dubbing/sfx/error
		mv -fv input/vr/dubbing/sfx/*.mp4 input/vr/dubbing/sfx/error
	fi

	#dubbing -> scaling
	#GLOBIGNORE="*_x?*.mp4"
	#[ $PIPELINE_AUTOFORWARD -ge 1 ] && mv -fv output/vr/dubbing/sfx/*.mp4 input/vr/scaling  >/dev/null 2>&1
	#unset GLOBIGNORE		
	

else
	  echo -e $"\e[91mError:\e[0m Wrong path to script. COMFYUIPATH=$COMFYUIPATH"
fi

