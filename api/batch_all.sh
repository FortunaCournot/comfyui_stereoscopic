#!/bin/sh
# Executes the whole SBS workbench pipeline
# Copyright (c) 2025 Fortuna Cournot. MIT License.

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).
# Prerequisite: Placed sbs_api.py somewhere and configured path variables below.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable
COMFYUIPATH=`realpath $(dirname "$0")/../../..`

cd $COMFYUIPATH

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

export CONFIGFILE
if [ -e $CONFIGFILE ] ; then
    config_version=$(awk -F "=" '/config_version/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
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
	echo -e $"\e[91mError:\e[0mComfyUI not present. Ensure it is running on port 8188"
elif [[ $FREESPACE -lt $MINSPACE ]] ; then
	echo -e $"\e[91mError:\e[0mLess than $MINSPACE""G left on device: $FREESPACE""G"
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
		echo -e $"\e[93mWarning:\e[0m Custom nodes ComfyUI-Florence2 could not be found. Use Custom Nodes Manager to install v1.0.5."
		DUBBING_DEP_ERROR="x"
	fi
	if [ ! -d custom_nodes/ComfyUI-MMAudio ] ; then
		echo -e $"\e[93mWarning:\e[0m Custom nodes ComfyUI-MMAudio could not be found at $COMFYUIPATH/custom_nodes/ComfyUI-MMAudio"
		echo -e $"It must be installed manually from \e[36mhttps://github.com/hkchengrex/MMAudio\e[0m"
		DUBBING_DEP_ERROR="x"
	fi
	if [ ! -d custom_nodes/was-node-suite-comfyui ] ; then
		echo -e $"\e[93mWarning:\e[0m Custom nodes was-node-suite could not be found at $COMFYUIPATH/custom_nodes/was-node-suite-comfyui"
		echo -e $"It must be installed manually from \e[36mhttps://github.com/WASasquatch/was-node-suite-comfyui\e[0m"
		DUBBING_DEP_ERROR="x"
	fi
	
	# LOCAL: prepare move output to next stage input (This should happen in daemon, too)
	mkdir -p input/vr/scaling input/vr/fullsbs

	# workaround for recovery problem.
	./custom_nodes/comfyui_stereoscopic/api/clear.sh
	

	SCALECOUNT=`find input/vr/scaling -maxdepth 1 -type f -name '*.mp4' | wc -l`
	OVERRIDECOUNT=`find input/vr/scaling/override -maxdepth 1 -type f -name '*.mp4' | wc -l`
	if [ $SCALECOUNT -ge 1 ] || [ $OVERRIDECOUNT -ge 1 ]; then
		# UPSCALING: Video -> Video. Limited to 60s and 4K.
		# In:  input/vr/scaling
		# Out: output/vr/scaling
		echo "**************************"
		echo "******** SCALING *********"
		echo "**************************"
		if [ $SCALECOUNT -ge 1 ]; then
			./custom_nodes/comfyui_stereoscopic/api/batch_scaling.sh
		fi
		if [ $OVERRIDECOUNT -ge 1 ]; then
			./custom_nodes/comfyui_stereoscopic/api/batch_scaling.sh /override
		fi
	fi

	# scaling -> fullsbs
	GLOBIGNORE="*_SBS_LR*.mp4"
	mv -f output/vr/scaling/*.mp4 output/vr/scaling/*.png output/vr/scaling/*.jpg output/vr/scaling/*.jpeg output/vr/scaling/*.PNG output/vr/scaling/*.JPG output/vr/scaling/*.JPEG input/vr/fullsbs  >/dev/null 2>&1
	unset GLOBIGNORE		


	SLIDECOUNT=`find input/vr/slides -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
	if [ $SLIDECOUNT -ge 2 ]; then
		# PREPARE 4K SLIDES
		# In:  input/vr/slides
		# Out: output/slides
		echo "**************************"
		echo "***** PREPARE SLIDES *****"
		echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_prepare_slides.sh
	fi
	
	# slides -> fullsbs
	GLOBIGNORE="*_SBS_LR*.*"
	mv -f output/vr/slides/*.* input/vr/fullsbs  >/dev/null 2>&1
	unset GLOBIGNORE		
	
	
	SBSCOUNT=`find input/vr/fullsbs -maxdepth 1 -type f -name '*.mp4' -o -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
	if [ $SBSCOUNT -ge 1 ]; then
		# SBS CONVERTER: Video -> Video, Image -> Image
		# In:  input/vr/fullsbs
		# Out: output/sbs
		echo "**************************"
		echo "*****  SBSCONVERTING *****"
		echo "**************************"
		SBS_DEPTH_SCALE=$(awk -F "=" '/SBS_DEPTH_SCALE/ {print $2}' $CONFIGFILE) ; SBS_DEPTH_SCALE=${SBS_DEPTH_SCALE:-"1.25"}
		SBS_DEPTH_OFFSET=$(awk -F "=" '/SBS_DEPTH_OFFSET/ {print $2}' $CONFIGFILE) ; SBS_DEPTH_OFFSET=${SBS_DEPTH_OFFSET:-"0.0"}
		./custom_nodes/comfyui_stereoscopic/api/batch_sbsconverter.sh $SBS_DEPTH_SCALE $SBS_DEPTH_OFFSET
	fi


	SINGLELOOPCOUNT=`find input/vr/singleloop -maxdepth 1 -type f -name '*.mp4' | wc -l`
	if [ $SINGLELOOPCOUNT -ge 1 ]; then
		# SINGLE LOOP
		# In:  input/vr/singleloop_in
		# Out: output/vr/singleloop
		echo "**************************"
		echo "****** SINGLE LOOP *******"
		echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_singleloop.sh
	fi

	
	SLIDESBSCOUNT=`find input/vr/slideshow -maxdepth 1 -type f -name '*.png' | wc -l`
	if [ $SLIDESBSCOUNT -ge 2 ]; then
		# MAKE SLIDESHOW
		# In:  input/vr/slideshow
		# Out: output/vr/slideshow
		echo "**************************"
		echo "***** MAKE SLIDESHOW *****"
		echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_make_slideshow.sh
	fi


	CONCATCOUNT=`find input/vr/concat -maxdepth 1 -type f -name '*.mp4' | wc -l`
	if [ $CONCATCOUNT -ge 1 ]; then
		# CONCAT
		# In:  input/vr/concat_in
		# Out: output/vr/concat
		echo "**************************"
		echo "******** CONCAT **********"
		echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_concat.sh
	fi

	### SKIP IF DEPENDENCY CHECK FAILED ###
	DUBCOUNT=`find input/vr/dubbing -maxdepth 1 -type f -name '*.mp4' | wc -l`
	if [[ -z $DUBBING_DEP_ERROR ]] && [ $DUBCOUNT -gt 0 ]; then
		# DUBBING: Video -> Video with SFX
		# In:  input/vr/dubbing
		# Out: output/vr/dubbing
		echo "**************************"
		echo "******** DUBBING *********"
		echo "**************************"
		./custom_nodes/comfyui_stereoscopic/api/batch_dubbing.sh
	fi

	# dubbing -> scaling
	#GLOBIGNORE="*_x?*.mp4"
	#mv -f output/vr/dubbing/*.mp4 input/vr/scaling  >/dev/null 2>&1
	#unset GLOBIGNORE		

else
	  echo "Wrong path to script. COMFYUIPATH=$COMFYUIPATH"
fi

