#!/bin/sh
# Creates SBS videos in batch from all base videos placed in ComfyUI/input/vr/watermark/encrypt folder (input)

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).


# relative or abolute path of ComfyUI folder in your ComfyUI_windows_portable
# Default: Executed in ComfyUI folder
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# relative to COMFYUIPATH:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/python/i2i_watermark_encrypt.py
# Use Systempath for python by default, but set it explictly for comfyui portable.
PYTHON_BIN_PATH=
if [ -d "../python_embeded" ]; then
  PYTHON_BIN_PATH=../python_embeded/
fi


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

# set FFMPEGPATHPREFIX if ffmpeg binary is not in your enviroment path
FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}


FREESPACE=$(df -khBG . | tail -n1 | awk '{print $4}')
FREESPACE=${FREESPACE%G}
MINSPACE=10
status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
if [ "$status" = "closed" ]; then
    echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
elif [[ $FREESPACE -lt $MINSPACE ]] ; then
	echo -e $"\e[91mError:\e[0m Less than $MINSPACE""G left on device: $FREESPACE""G"
elif test $# -ne 0; then
    # targetprefix path is relative; parent directories are created as needed
    echo "Usage: $0 "
    echo "E.g.: $0 "
else
	mkdir -p output/vr/watermark/encrypt


	#for file in input/vr/watermark/encrypt/*' '*
	#do
	#	if [ -e "${file// /_}" ]
	#	then
	#		echo -e $"\e[91mError:\e[0m skipping $file as the renamed version already exists"
	#		mkdir -p input/vr/watermark/encrypt/error
	#		mv -- "$file" input/vr/watermark/encrypt/error
	#		continue
	#	fi
	#
	#	mv -- "$file" "${file// /_}"
	#done

	for f in input/vr/watermark/encrypt/*\ *; do mv -- "$f" "${f// /_}"; done 2>/dev/null
	for f in input/vr/watermark/encrypt/*\(*; do mv -- "$f" "${f//\(/_}"; done 2>/dev/null
	for f in input/vr/watermark/encrypt/*\)*; do mv -- "$f" "${f//\)/_}"; done 2>/dev/null
	for f in input/vr/watermark/encrypt/*\'*; do mv -- "$f" "${f//\'/_}"; done 2>/dev/null

	WATERMARK_SECRETKEY=$(awk -F "=" '/WATERMARK_SECRETKEY/ {print $2}' $CONFIGFILE) ; WATERMARK_SECRETKEY=${WATERMARK_SECRETKEY:-"-1"}
	WATERMARK_LABEL=$(awk -F "=" '/WATERMARK_LABEL/ {print $2}' $CONFIGFILE) ; WATERMARK_LABEL=${WATERMARK_LABEL:-""}
	WATERMARK_LABEL="${WATERMARK_LABEL//[^[:alnum:].]/_}"
	WATERMARK_LABEL="${WATERMARK_LABEL:0:17}"
	WATERMARK_STOREFOLDER=./user/default/comfyui_stereoscopic/watermark/$WATERMARK_SECRETKEY
	mkdir -p $WATERMARK_STOREFOLDER
	
	uuid=$(openssl rand -hex 16)
	INTERMEDIATEFOLDER=input/vr/watermark/encrypt/intermediate/$uuid
	mkdir -p $INTERMEDIATEFOLDER
	
	if [ ! -e "$WATERMARK_STOREFOLDER/watermark.png" ]; then
		nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i ./user/default/comfyui_stereoscopic/watermark_background.png -filter_complex "[0:0]crop=1024:1024:0:0[img];color=c=0xffffff@0x00:s=1000x1000,format=rgba,drawtext=text='$WATERMARK_LABEL':fontcolor=white: fontsize=100:x=(w-text_w)/2:y=32[fg];[img][fg]overlay=0:0:format=rgb,format=rgba[out]" -map [out] -c:v png -frames:v 1 $WATERMARK_STOREFOLDER/watermark.png
		if [ ! -e "$WATERMARK_STOREFOLDER/watermark.png" ]; then
			echo -e $"\e[91mError:\e[0m Failed to create watermark"
			exit
		fi
	fi
	
	mkdir -p output/vr/watermark/encrypt/intermediate
	
	COUNT=`find input/vr/watermark/encrypt -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' | wc -l`
	declare -i INDEX=0
	if [[ $COUNT -gt 0 ]] ; then
		VIDEOFILES=`find input/vr/watermark/encrypt -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm'`
		for nextinputfile in $VIDEOFILES ; do
			INDEX+=1
			echo "$INDEX/$COUNT">input/vr/watermark/encrypt/BATCHPROGRESS.TXT
			newfn=${nextinputfile##*/}
			newfn=${newfn//[^[:alnum:].]/_}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			newfn=$INTERMEDIATEFOLDER/$newfn
			mv -- "$nextinputfile" $newfn 
			
			TARGETPREFIX=${newfn##*/}
			
			# /bin/bash $SCRIPTPATH  "$newfn" WatermarkImagePath OutputPathPrefix secret
			
		done
		rm  -f input/vr/watermark/encrypt/BATCHPROGRESS.TXT 
	fi	

	IMGFILES=`find input/vr/watermark/encrypt -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG'`
	COUNT=`find input/vr/watermark/encrypt -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
	INDEX=0
	rm -f intermediateimagefiles.txt
	if [[ $COUNT -gt 0 ]] ; then
		for nextinputfile in $IMGFILES ; do
			if [ ! -e $nextinputfile ] ; then
				echo -e $"\e[91mError:\e[0m File removed. Batch task terminated."
				exit
			fi
			INDEX+=1
			echo "$INDEX/$COUNT">input/vr/watermark/encrypt/BATCHPROGRESS.TXT
			newfn=${nextinputfile##*/}
			newfn=${newfn//[^[:alnum:].]/_}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			STORENAME=$newfn
			newfn=$INTERMEDIATEFOLDER/$newfn
			mv -- "$nextinputfile" $newfn 
			
			if [ -e "$newfn" ]; then
				TARGETPREFIX=${newfn##*/}
				TARGETPREFIX=${TARGETPREFIX%.*}
				
				echo -ne $"\e[91m" ; "$PYTHON_BIN_PATH"python.exe $SCRIPTPATH  `realpath "$newfn"` `realpath "$WATERMARK_STOREFOLDER/watermark.png"` "vr/watermark/encrypt/intermediate/$TARGETPREFIX" $WATERMARK_SECRETKEY ; echo -ne $"\e[0m"
				
				status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
				if [ "$status" = "closed" ]; then
					echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
					mkdir input/vr/watermark/encrypt/error
					mv "$newfn" input/vr/watermark/encrypt/error
					rm -rf $INTERMEDIATEFOLDER
					exit
				fi
				
				until [ "$queuecount" = "0" ]
				do
					sleep 1
					curl -silent "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json
					queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
				done				
				
				if [ -e "output/vr/watermark/encrypt/intermediate/$TARGETPREFIX""_00001_.png" ]; then
					if [ -e "$WATERMARK_STOREFOLDER/$STORENAME" ]; then
						echo -e "$INDEX/$COUNT: "$"\e[91mFailed: Source file already in storage!\e[0m ""$WATERMARK_STOREFOLDER/$STORENAME""                      "
						mkdir input/vr/watermark/encrypt/error
						mv "$newfn" input/vr/watermark/encrypt/error
					else
						mv -vf "$newfn" "$WATERMARK_STOREFOLDER/$STORENAME"
						mv -vf "output/vr/watermark/encrypt/intermediate/$TARGETPREFIX""_00001_.png" "output/vr/watermark/encrypt/$TARGETPREFIX""_marked.png"
						echo -e "$INDEX/$COUNT: "$"\e[92mdone:\e[0m $TARGETPREFIX. Original stored in $WATERMARK_STOREFOLDER                     "
					fi
				else
					echo -e "$INDEX/$COUNT: "$"\e[91mfailed to fetch result at:\e[0m ""output/vr/watermark/encrypt/intermediate/$TARGETPREFIX""_00001_.png""                      "
					mkdir input/vr/watermark/encrypt/error
					mv "$newfn" input/vr/watermark/encrypt/error
				fi
			else
				echo -e $"\e[91mError:\e[0m prompting failed. Missing file: $newfn"
			fi			
		done
		rm  -f input/vr/watermark/encrypt/BATCHPROGRESS.TXT 
				
	fi	
	rm -rf $INTERMEDIATEFOLDER
	echo "Batch done."
fi
