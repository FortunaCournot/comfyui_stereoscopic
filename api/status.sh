#!/bin/sh
# Executes the whole SBS workbench pipeline again and again ...
# Copyright (c) 2025 Fortuna Cournot. MIT License.

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
	COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
	COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
	export COMFYUIHOST COMFYUIPORT
else
    touch "$CONFIGFILE"
    echo "config_version=1">>"$CONFIGFILE"
fi


echo -e $"\e[4m+++ Summary of Disk Usage +++\e[0m"
du -s -BG *put/vr
echo " "

# Report completed files
du --inodes -d 0 -S output/vr/*           | { while read inodes path; do files=`ls -F $path |grep -v / | wc -l`; [ $files -gt 0 ] && printf "%s\t%s\n" `[ $files -gt 0 ] && echo $files || echo "-"` "$path"; done } >user/default/comfyui_stereoscopic/tmplog
du --inodes -d 0 -S output/vr/dubbing/*   | { while read inodes path; do files=`ls -F $path |grep -v / | wc -l`; [ $files -gt 0 ] && printf "%s\t%s\n" `[ $files -gt 0 ] && echo $files || echo "-"` "$path"; done } >>user/default/comfyui_stereoscopic/tmplog
logsize=`stat -c %s user/default/comfyui_stereoscopic/tmplog`
if [[ $logsize -gt 0 ]] ; then
	echo -e $"\e[4m\e[32m+++ Summary of Completed Files per Folder +++\e[0m\e[92m"
	cat user/default/comfyui_stereoscopic/tmplog
	#du --inodes -d 0 -S output/vr/*/final | { while read inodes path; do files=`ls -F $path |grep -v / | wc -l`; printf "%s\t%s\n" `[ $files -gt 0 ] && echo $files || echo "-"` "$path"; done }
	echo -ne $"\e[0m"
fi
rm user/default/comfyui_stereoscopic/tmplog

find input/vr -type d -name error -o -name stopped  | { while read path; do files=`ls -F $path |grep -v / |grep [.] | wc -l`; [ $files -gt 0 ] && printf "%s\t%s\n" `[ $files -gt 0 ] && echo $files || echo "-"` "$path"; done } | wc -l >.tmperrcount
ERRFOLDERCOUNT=`cat .tmperrcount`
rm .tmperrcount
if [[ "$ERRFOLDERCOUNT" -gt 0 ]] ; then
	echo " "
	echo -e $"\e[31m\e[4m+++ Summary of Folders with Errors +++\e[0m"
	echo -ne "\e[91m"
	find input/vr -type d -name error  | { while read path; do files=`ls -F $path |grep -v / | wc -l`; [ $files -gt 0 ] && printf "%s\t%s\n" `[ $files -gt 0 ] && echo $files || echo "-"` "$path"; done }
	echo -ne $"\e[0m\e[93m"
	find input/vr -type d -name stopped | { while read path; do files=`ls -F $path |grep -v / | wc -l`; [ $files -gt 0 ] && printf "%s\t%s\n" `[ $files -gt 0 ] && echo $files || echo "-"` "$path"; done }
	echo -ne $"\e[0m"
fi
exit 0
