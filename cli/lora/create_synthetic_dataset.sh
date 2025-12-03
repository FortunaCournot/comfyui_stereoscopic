#!/bin/sh
# Create testdata for I2V LoRA by creating videos from images created from T2I model and LoRA

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).

onExit() {
	exit_code=$?
	exit $exit_code
}
trap onExit EXIT

# relative or abolute path of ComfyUI folder in your ComfyUI_windows_portable
# Default: Executed in ComfyUI folder
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../../..`
# relative to COMFYUIPATH:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/cli/lora/python/create_synthetic_dataset.py
WORKFLOWPATH=./user/default/workflows/Create_Synthetic_Testdata_SD1.5_API.json

cd $COMFYUIPATH

# Use Systempath for python by default, but set it explictly for comfyui portable.
PYTHON_BIN_PATH=
if [ -d "../python_embeded" ]; then
  PYTHON_BIN_PATH=../python_embeded/
fi


CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

export CONFIGFILE
if [ -e $CONFIGFILE ] ; then
	loglevel=$(awk -F "=" '/loglevel=/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
	[ $loglevel -ge 2 ] && set -x
    config_version=$(awk -F "=" '/config_version=/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
	COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST=/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
	COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT=/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
	
else
  COMFYUIHOST=192.168.0.99
  COMFYUIPORT=8188
fi
export COMFYUIHOST COMFYUIPORT

cp -n ./custom_nodes/comfyui_stereoscopic/cli/lora/files/Create_Synthetic_Testdata_SD1.5_API.json $WORKFLOWPATH

PYTHON_BIN_PATH=`realpath $PYTHON_BIN_PATH`
SCRIPTPATH=`realpath $SCRIPTPATH`
WORKFLOWPATH=`realpath $WORKFLOWPATH`
OUTPUTDIR=`realpath "./output/vr/tasks/forwarder"`

echo "# --- Modifiy and execute the following commands: ---"
echo export COMFYUIHOST=$COMFYUIHOST
echo export COMFYUIPORT=$COMFYUIPORT
echo \"$PYTHON_BIN_PATH/python\" \"$SCRIPTPATH\" \
    --workflow \""$WORKFLOWPATH\"" \
    --tests 1 \
    --prompt_text \"a robot with glowing blue eyes in dramatic cinematic lighting.\" \
    --target_length 17 \
    --iterations 4 \
    --startvalue 3.0 \
    --endvalue -2.0 \
    --output_dir \"$OUTPUTDIR\"
    
    