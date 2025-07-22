#!/bin/sh
# Executes the whole SBS workbench pipeline
# Copyright (c) 2025 Fortuna Cournot. MIT License.

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).
# Prerequisite: Placed sbs_api.py somewhere and configured path variables below.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable
COMFYUIPATH=.

cd $COMFYUIPATH

FREESPACE=$(df -khBG . | tail -n1 | awk '{print $4}')
FREESPACE=${FREESPACE%G}
MINSPACE=10
status=`true &>/dev/null </dev/tcp/127.0.0.1/8188 && echo open || echo closed`
if test $# -ne 0
then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 "
    echo "E.g.: $0 "
elif [ "$status" = "closed" ]; then
	echo "Error: ComfyUI not present. Ensure it is running on port 8188"
elif [[ $FREESPACE -lt $MINSPACE ]] ; then
	echo "Error: Less than $MINSPACE""G left on device: $FREESPACE""G"
elif [ -d "custom_nodes" ]; then

	echo "****************************************************"
	
	# SLIDESHOW: 2+ Images -> 4K Video
	# In:  input/slideshow_in
	# Out: output/slideshow	
	echo "**************************"
	echo "******* SLIDESHOW ********"
	echo "**************************"
    ./custom_nodes/comfyui_stereoscopic/api/batch_makeslideshow.sh
	# move to next stage
	mkdir -p input/dubbing
	mv -f output/slideshow/*.mp4 input/dubbing_in  >/dev/null 2>&1
	
	# DUBBING: Video -> Video with SFX
	# In:  input/dubbing_in
	# Out: output/dubbing
	# Config: input/dubbing_in/positive.txt, input/dubbing_in/negative.txt
	echo "**************************"
	echo "******** DUBBING *********"
	echo "**************************"
    ./custom_nodes/comfyui_stereoscopic/api/batch_dubbing.sh
	# move to next stage
	mkdir -p output/dubbing/sbs
	mv -f output/dubbing/*SBS_LR.mp4 output/dubbing/sbs  >/dev/null 2>&1
	mv -f output/dubbing/*.mp4 input/upscale_in  >/dev/null 2>&1
	
	# UPSCALING: Video -> Video. Limited to 10s and 4K.
	# In:  input/upscale_in
	# Out: output/upscale
	echo "**************************"
	echo "******* UPSCALING ********"
	echo "**************************"
    ./custom_nodes/comfyui_stereoscopic/api/batch_upscale.sh
	# move to next stage
	mv -f output/upscale/*.mp4 output/dubbing/*.png output/dubbing/*.jpg output/dubbing/*.jpeg output/dubbing/*.PNG output/dubbing/*.JPG output/dubbing/*.JPEG input/sbs_in  >/dev/null 2>&1
	
	# SBS CONVERTER: Video -> Video, Image -> Image
	# In:  input/sbs_in
	# Out: output/sbs
	echo "**************************"
	echo "*****  SBSCONVERTING *****"
	echo "**************************"
	./custom_nodes/comfyui_stereoscopic/api/batch_sbsconverter.sh 1.25 0
	
else
	  echo "Wrong path to script. COMFYUIPATH=$COMFYUIPATH"
fi

