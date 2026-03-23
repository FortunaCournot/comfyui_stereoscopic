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
  #echo "Running cleanup..."
  exit 0 # Exit the script after cleanup
}

trap cleanup EXIT

source ./user/default/comfyui_stereoscopic/.environment

echo "Restarting gui ..."
touch user/default/comfyui_stereoscopic/.guiactive
rm -f user/default/comfyui_stereoscopic/.guierror 2>/dev/null
OPENCV_FFMPEG_READ_ATTEMPTS=8192
export OPENCV_FFMPEG_READ_ATTEMPTS
# Start GUI detached so terminal focus events / control sequences
# are not visible in the current shell. Prefer `nohup`, then `setsid`,
# otherwise background + disown as a fallback. Log stdout/stderr for debugging.
mkdir -p user/default/comfyui_stereoscopic
LOGFILE=user/default/comfyui_stereoscopic/gui.log
if command -v nohup >/dev/null 2>&1; then
  nohup "${PYTHON_BIN_PATH}python.exe" "$SCRIPTPATH" >> "$LOGFILE" 2>&1 &
  GUI_PID=$!
elif command -v setsid >/dev/null 2>&1; then
  setsid "${PYTHON_BIN_PATH}python.exe" "$SCRIPTPATH" >> "$LOGFILE" 2>&1 &
  GUI_PID=$!
else
  "${PYTHON_BIN_PATH}python.exe" "$SCRIPTPATH" >> "$LOGFILE" 2>&1 &
  GUI_PID=$!
  disown $GUI_PID 2>/dev/null || true
fi
# When the GUI process exits, remove the guiactive flag (watcher runs detached)
( wait $GUI_PID; rm -f -- user/default/comfyui_stereoscopic/.guiactive ) &

echo "Waiting for gui or daemon to shutdown..."
while [ -e user/default/comfyui_stereoscopic/.daemonactive ] && [ -e user/default/comfyui_stereoscopic/.guiactive ]; do
	sleep 1
done
sleep 1
if [ -e user/default/comfyui_stereoscopic/.guierror ] ; then echo "Press CTRL + C" ; fi
while [ -e user/default/comfyui_stereoscopic/.guierror ]; do
	sleep 1
done