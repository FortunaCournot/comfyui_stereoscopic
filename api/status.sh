#!/bin/sh
# Executes the whole SBS workbench pipeline again and again ...
# Copyright (c) 2025 Fortuna Cournot. MIT License.

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
else
    touch "$CONFIGFILE"
    echo "config_version=1">>"$CONFIGFILE"
fi

echo -e $"\e[4m+++ Summary of completed files per folder +++\e[0m"
du --inodes -d 0 -S output/vr/*       | { while read inodes path; do files=`ls -F $path |grep -v / | wc -l`; printf "%s\t%s\n" "$files" "$path"; done }
du --inodes -d 0 -S output/vr/*/final | { while read inodes path; do files=`ls -F $path |grep -v / | wc -l`; printf "%s\t%s\n" "$files" "$path"; done }
