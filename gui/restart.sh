#!/bin/bash

if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# relative to COMFYUIPATH:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/gui/python/vrweare.py

cd $COMFYUIPATH
# Use Systempath for python by default, but set it explictly for comfyui portable.
PYTHON_BIN_PATH=
if [ -d "../python_embeded" ]; then
  PYTHON_BIN_PATH=../python_embeded/
fi

cleanup() {
    #echo "Reinigung wird durchgeführt..."
    exit 0 # Beendet das Skript nach der Bereinigung
}

trap cleanup EXIT

echo "Restarting gui ..."
touch user/default/comfyui_stereoscopic/.guiactive
rm -f user/default/comfyui_stereoscopic/.guierror 2>/dev/null
OPENCV_FFMPEG_READ_ATTEMPTS=8192
export OPENCV_FFMPEG_READ_ATTEMPTS
"$PYTHON_BIN_PATH"python.exe $SCRIPTPATH && rm -f -- user/default/comfyui_stereoscopic/.guiactive &

echo "Waiting for gui or daemon to shutdown..."
while [ -e user/default/comfyui_stereoscopic/.daemonactive ] && [ -e user/default/comfyui_stereoscopic/.guiactive ]; do
	sleep 1
done
sleep 1
if [ -e user/default/comfyui_stereoscopic/.guierror ] ; then echo "Press CTRL + C" ; fi
while [ -e user/default/comfyui_stereoscopic/.guierror ]; do
	sleep 1
done