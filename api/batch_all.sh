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
	
	echo "**************************"
	echo "******** DUBBING *********"
	echo "**************************"
    ./custom_nodes/comfyui_stereoscopic/api/batch_dubbing.sh
	
	echo "**************************"
	echo "******* UPSCALING ********"
	echo "**************************"
    ./custom_nodes/comfyui_stereoscopic/api/batch_upscale.sh
	
	echo "**************************"
	echo "*****  SBSCONVERTING *****"
	echo "**************************"
	./custom_nodes/comfyui_stereoscopic/api/batch_sbsconverter.sh 1.25 0
	
else
	  echo "Wrong path to script. COMFYUIPATH=$COMFYUIPATH"
fi

