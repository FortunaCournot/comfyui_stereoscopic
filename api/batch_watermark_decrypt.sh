#!/bin/sh
# Extracts forensic watermark from images and videos, based on source files and watermark from storage.

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).

onExit() {
	exit_code=$?
	exit $exit_code
}
trap onExit EXIT

# relative or abolute path of ComfyUI folder in your ComfyUI_windows_portable
# Default: Executed in ComfyUI folder
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# relative to COMFYUIPATH:
SCRIPTPATH=./custom_nodes/comfyui_stereoscopic/api/python/i2i_watermark_decrypt.py
# Use Systempath for python by default, but set it explictly for comfyui portable.
PYTHON_BIN_PATH=
if [ -d "../python_embeded" ]; then
  PYTHON_BIN_PATH=../python_embeded/
fi


cd $COMFYUIPATH

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

export CONFIGFILE
if [ -e $CONFIGFILE ] ; then
	loglevel=$(awk -F "=" '/loglevel=/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
	[ $loglevel -ge 2 ] && set -x
    config_version=$(awk -F "=" '/config_version=/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
	COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST=/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
	COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT=/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
	export COMFYUIHOST COMFYUIPORT
else
    touch "$CONFIGFILE"
    echo "config_version=1">>"$CONFIGFILE"
fi

# set FFMPEGPATHPREFIX if ffmpeg binary is not in your enviroment path
FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX=/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}


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
	mkdir -p output/vr/watermark/decrypt


	#for file in input/vr/watermark/decrypt/*' '*
	#do
	#	if [ -e "${file// /_}" ]
	#	then
	#		echo -e $"\e[91mError:\e[0m skipping $file as the renamed version already exists"
	#		mkdir -p input/vr/watermark/decrypt/error
	#		mv -- "$file" input/vr/watermark/decrypt/error
	#		continue
	#	fi
	#
	#	mv -- "$file" "${file// /_}"
	#done

	for f in input/vr/watermark/decrypt/*\ *; do mv -- "$f" "${f// /_}"; done 2>/dev/null
	for f in input/vr/watermark/decrypt/*\(*; do mv -- "$f" "${f//\(/_}"; done 2>/dev/null
	for f in input/vr/watermark/decrypt/*\)*; do mv -- "$f" "${f//\)/_}"; done 2>/dev/null
	for f in input/vr/watermark/decrypt/*\'*; do mv -- "$f" "${f//\'/_}"; done 2>/dev/null

	WATERMARK_SECRETKEY=$(awk -F "=" '/WATERMARK_SECRETKEY=/ {print $2}' $CONFIGFILE) ; WATERMARK_SECRETKEY=${WATERMARK_SECRETKEY:-"-1"}
	WATERMARK_LABEL=$(awk -F "=" '/WATERMARK_LABEL=/ {print $2}' $CONFIGFILE) ; WATERMARK_LABEL=${WATERMARK_LABEL:-""}
	WATERMARK_LABEL="${WATERMARK_LABEL//[^[:alnum:].-]/_}"
	WATERMARK_LABEL="${WATERMARK_LABEL:0:17}"
	WATERMARK_STOREFOLDER=./user/default/comfyui_stereoscopic/watermark/$WATERMARK_SECRETKEY
	mkdir -p $WATERMARK_STOREFOLDER
	
	uuid=$(openssl rand -hex 16)
	INTERMEDIATEFOLDER=input/vr/watermark/decrypt/intermediate/$uuid
	mkdir -p $INTERMEDIATEFOLDER
	
	if [ ! -e "$WATERMARK_STOREFOLDER/watermark.png" ]; then
		nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y -i ./user/default/comfyui_stereoscopic/watermark_background.png -filter_complex "[0:0]crop=1024:1024:0:0[img];color=c=0xffffff@0x00:s=1000x1000,format=rgba,drawtext=text='$WATERMARK_LABEL':fontcolor=white: fontsize=100:x=(w-text_w)/2:y=32[fg];[img][fg]overlay=0:0:format=rgb,format=rgba[out]" -map [out] -c:v png -frames:v 1 $WATERMARK_STOREFOLDER/watermark.png
		if [ ! -e "$WATERMARK_STOREFOLDER/watermark.png" ]; then
			echo -e $"\e[91mError:\e[0m Failed to create watermark"
			exit 1
		fi
	fi
	
	mkdir -p output/vr/watermark/decrypt/intermediate
	
	COUNT=0 #`find input/vr/watermark/decrypt -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' | wc -l`
	declare -i INDEX=0
	if [[ $COUNT -gt 0 ]] ; then
		VIDEOFILES=`find input/vr/watermark/decrypt -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm'`
		for nextinputfile in $VIDEOFILES ; do
			INDEX+=1
			echo "$INDEX/$COUNT">input/vr/watermark/decrypt/BATCHPROGRESS.TXT
			echo "watermark/decrypt" >user/default/comfyui_stereoscopic/.daemonstatus
			echo "video $INDEX of $COUNT" >>user/default/comfyui_stereoscopic/.daemonstatus
			newfn=${nextinputfile##*/}
			newfn=${newfn//[^[:alnum:].-]/_}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			newfn=$INTERMEDIATEFOLDER/$newfn
			mv -- "$nextinputfile" $newfn 
			
			TARGETPREFIX=${newfn##*/}
			
			# /bin/bash $SCRIPTPATH  "$newfn" WatermarkImagePath OutputPathPrefix secret
			
		done
		rm  -f input/vr/watermark/decrypt/BATCHPROGRESS.TXT 
	fi	

	IMGFILES=`find input/vr/watermark/decrypt -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG'`
	COUNT=`find input/vr/watermark/decrypt -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
	INDEX=0
	rm -f intermediateimagefiles.txt
	if [[ $COUNT -gt 0 ]] ; then
		for nextinputfile in $IMGFILES ; do
			if [ ! -e $nextinputfile ] ; then
				echo -e $"\e[91mError:\e[0m File removed. Batch task terminated."
				exit 1
			fi
			INDEX+=1
			echo "watermark/decrypt" >user/default/comfyui_stereoscopic/.daemonstatus
			echo "image $INDEX of $COUNT" >>user/default/comfyui_stereoscopic/.daemonstatus
			
			regex="[^/]*$"
			echo "========== $INDEX/$COUNT"" decode "`echo $nextinputfile | grep -oP "$regex"`" =========="

			newfn=${nextinputfile##*/}
			newfn=${newfn//[^[:alnum:].-]/_}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			STORENAME=$newfn
			
			if [ ! -e "$WATERMARK_STOREFOLDER/$STORENAME" ]; then
				echo -e "$INDEX/$COUNT: "$"\e[91mFailed: Source file not found in storage. Expected location: \e[0m ""$WATERMARK_STOREFOLDER/$STORENAME""                      "
				mkdir input/vr/watermark/decrypt/error
				mv "$nextinputfile" input/vr/watermark/decrypt/error
				exit 0
			fi
			
			newfn=$INTERMEDIATEFOLDER/$newfn
			mv -- "$nextinputfile" $newfn 
			
			if [ -e "$newfn" ]; then
				TARGETPREFIX=${newfn##*/}
				TARGETPREFIX=${TARGETPREFIX%.*}
				
				#OriginalImagePath EncryptedImagePath WatermarkOutputPathPrefix secre
				echo -ne $"\e[91m" ; "$PYTHON_BIN_PATH"python.exe $SCRIPTPATH `realpath "$WATERMARK_STOREFOLDER/$STORENAME"` `realpath "$newfn"` "vr/watermark/decrypt/intermediate/$TARGETPREFIX" $WATERMARK_SECRETKEY ; echo -ne $"\e[0m"
				
				status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
				if [ "$status" = "closed" ]; then
					echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
					mkdir input/vr/watermark/decrypt/error
					mv "$newfn" input/vr/watermark/decrypt/error
					rm -rf $INTERMEDIATEFOLDER
					exit 0
				fi
				
				until [ "$queuecount" = "0" ]
				do
					sleep 1
					curl -silent "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json
					queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
				done				
				
				if [ -e "output/vr/watermark/decrypt/intermediate/$TARGETPREFIX""_00001_.png" ]; then
					mv -vf "output/vr/watermark/decrypt/intermediate/$TARGETPREFIX""_00001_.png" "output/vr/watermark/decrypt/$TARGETPREFIX""_test.png"
					echo -e "$INDEX/$COUNT: "$"\e[92mdone:\e[0m $TARGETPREFIX. Watermark testfile extracted.                     "
				else
					echo -e "$INDEX/$COUNT: "$"\e[91mfailed to fetch result at:\e[0m ""output/vr/watermark/decrypt/intermediate/$TARGETPREFIX""_00001_.png""                      "
					mkdir input/vr/watermark/decrypt/error
					mv "$newfn" input/vr/watermark/decrypt/error
				fi
			else
				echo -e $"\e[91mError:\e[0m prompting failed. Missing file: $newfn"
			fi			
		done
				
	fi	
	rm -rf $INTERMEDIATEFOLDER
	echo "Batch done."
fi
exit 0
