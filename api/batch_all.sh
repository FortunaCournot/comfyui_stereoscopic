#!/bin/sh
# Executes the whole SBS workbench pipeline
# Copyright (c) 2025 Fortuna Cournot. MIT License.

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).
# Prerequisite: Placed sbs_api.py somewhere and configured path variables below.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable
COMFYUIPATH=.

cd $COMFYUIPATH

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

export CONFIGFILE
if [ -e $CONFIGFILE ] ; then
    config_version=$(awk -F "=" '/config_version/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
	COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
	COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
	export COMFYUIHOST COMFYUIPORT
	echo "config_version : $config_version"
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
	echo -e $"\e[31mError:\e[0mComfyUI not present. Ensure it is running on port 8188"
elif [[ $FREESPACE -lt $MINSPACE ]] ; then
	echo -e $"\e[31mError:\e[0mLess than $MINSPACE""G left on device: $FREESPACE""G"
	echo "trying to remove intermediate files..."
	rm -rf output/*/intermediate/*
elif [ -d "custom_nodes" ]; then


	# PREPARE 4K SLIDES
	# In:  input/vr/slides
	# Out: output/slides
	echo "**************************"
	echo "***** PREPARE SLIDES *****"
	echo "**************************"
    ./custom_nodes/comfyui_stereoscopic/api/batch_prepare_slides.sh
	# move to next stage
	mkdir -p input/vr/slideshow
	mv -f output/slides/*.* input/vr/fullsbs  >/dev/null 2>&1
	
	# DUBBING: Video -> Video with SFX
	# In:  input/vr/dubbing
	# Out: output/vr/dubbing
	# Config: input/vr/dubbing/positive.txt, input/vr/dubbing/negative.txt
	echo "**************************"
	echo "******** DUBBING *********"
	echo "**************************"
    ./custom_nodes/comfyui_stereoscopic/api/batch_dubbing.sh
	# move to next stage
	mkdir -p output/vr/dubbing/final
	mv -f output/vr/dubbing/*SBS_LR*.mp4 output/vr/dubbing/final  >/dev/null 2>&1
	mv -f output/vr/dubbing/*.mp4 input/vr/scaling  >/dev/null 2>&1
	
	# UPSCALING: Video -> Video. Limited to 60s and 4K.
	# In:  input/vr/scaling
	# Out: output/vr/scaling
	echo "**************************"
	echo "******** SCALING *********"
	echo "**************************"
    ./custom_nodes/comfyui_stereoscopic/api/batch_scaling.sh
    ./custom_nodes/comfyui_stereoscopic/api/batch_scaling.sh /override
	# move to next stage
	mv -f output/vr/scaling/*.mp4 output/vr/scaling/*.png output/vr/scaling/*.jpg output/vr/scaling/*.jpeg output/vr/scaling/*.PNG output/vr/scaling/*.JPG output/vr/scaling/*.JPEG input/vr/fullsbs  >/dev/null 2>&1
	# prepare input of previous stage for cleanup
	mkdir -p output/vr/dubbing/intermediate/dubbing_in
	# PRIMARY INPUT NOT MOVED BY DEFAULT # mv -f input/vr/dubbing/done/*.* output/vr/dubbing/intermediate/dubbing_in  >/dev/null 2>&1
	
	# SBS CONVERTER: Video -> Video, Image -> Image
	# In:  input/vr/fullsbs
	# Out: output/sbs
	echo "**************************"
	echo "*****  SBSCONVERTING *****"
	echo "**************************"
	./custom_nodes/comfyui_stereoscopic/api/batch_sbsconverter.sh 1.25 0
	# move to next stage
	mkdir -p input/vr/slideshow
	mkdir -p output/vr/fullsbs
	mv -f output/vr/fullsbs/*.* output/vr/fullsbs  >/dev/null 2>&1
	#mv -f output/vr/fullsbs/*.* input/vr/slideshow  >/dev/null 2>&1
	#mv -f output/vr/fullsbs/final/*.mp4 output/vr/fullsbs  >/dev/null 2>&1
	# prepare input of previous stage for cleanup
	mkdir -p output/vr/scaling/intermediate/upscale_in
	mv -f input/vr/scaling/done/*.* output/vr/scaling/intermediate/upscale_in  >/dev/null 2>&1
	
	# MAKE SLIDESHOW
	# In:  input/vr/slideshow
	# Out: output/vr/slideshow
	echo "**************************"
	echo "***** MAKE SLIDESHOW *****"
	echo "**************************"
    ./custom_nodes/comfyui_stereoscopic/api/batch_make_slideshow.sh
	# prepare input of previous stage for cleanup
	mkdir -p output/slides/intermediate/slide_in
	# PRIMARY INPUT NOT MOVED BY DEFAULT # mv -f input/slide_in/done/*.* output/slides/intermediate/slide_in  >/dev/null 2>&1
	mkdir -p output/vr/slideshow/intermediate/slideshow_in
	mv -f input/vr/slideshow/done/*.* output/vr/slideshow/intermediate/slideshow_in  >/dev/null 2>&1
	
	# SINGLE LOOP
	# In:  input/loop_in
	# Out: output/loop
	echo "**************************"
	echo "******* LOOP VIDEO *******"
	echo "**************************"
    ./custom_nodes/comfyui_stereoscopic/api/batch_single_loop.sh
	mkdir -p input/vr/dubbing
	mv -f output/vr/singleloop/*.* input/vr/dubbing  >/dev/null 2>&1
else
	  echo "Wrong path to script. COMFYUIPATH=$COMFYUIPATH"
fi

