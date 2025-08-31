#!/bin/bash

if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# relative to COMFYUIPATH:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/python/status_gui.py

cd $COMFYUIPATH
# Use Systempath for python by default, but set it explictly for comfyui portable.
PYTHON_BIN_PATH=
if [ -d "../python_embeded" ]; then
  PYTHON_BIN_PATH=../python_embeded/
fi

cleanup() {
    echo "Reinigung wird durchgeführt..."
    exit 0 # Beendet das Skript nach der Bereinigung
}

trap cleanup EXIT

echo "Restarting gui ..."
"$PYTHON_BIN_PATH"python.exe $SCRIPTPATH &

while [ -e user/default/comfyui_stereoscopic/.daemonactive ]; do
	sleep 5
done
