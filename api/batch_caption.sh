#!/bin/sh
# Attaches caption to images and video metadata.

# Prerequisite: local ComfyUI_windows_portable server must be running (on default port).


# relative or abolute path of ComfyUI folder in your ComfyUI_windows_portable
# Default: Executed in ComfyUI folder
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`
# relative to COMFYUIPATH:
SCRIPTPATH2=./custom_nodes/comfyui_stereoscopic/api/python/i2t_caption.py
SCRIPTPATH3=./custom_nodes/comfyui_stereoscopic/api/python/translate.py
# Use Systempath for python by default, but set it explictly for comfyui portable.

CAPTION_TIMEOUT=30

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

# CHECK TOOLS
EXIFTOOLBINARY=$(awk -F "=" '/EXIFTOOLBINARY=/ {print $2}' $CONFIGFILE) ; EXIFTOOLBINARY=${EXIFTOOLBINARY:-""}
if [ ! -e "$EXIFTOOLBINARY" ]; then
	echo -e $"\e[91mError:\e[0m Exiftool not found or properly configured. Set EXIFTOOLBINAR in"
	echo -e $"\e[91m      \e[0m $CONFIGFILE"
	echo -e $"\e[94m      \e[0m You may download Exiftool by visiting \e[36mhttps://exiftool.org\e[0m"
	echo -e $"\e[94m      \e[0m The Exif tool binary must be renamed to exiftool.exe. Strip '(-k)' from name."
	exit 1
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
	mkdir -p output/vr/caption



	for f in input/vr/caption/*\ *; do mv -- "$f" "${f// /_}"; done 2>/dev/null
	for f in input/vr/caption/*\(*; do mv -- "$f" "${f//\(/_}"; done 2>/dev/null
	for f in input/vr/caption/*\)*; do mv -- "$f" "${f//\)/_}"; done 2>/dev/null
	for f in input/vr/caption/*\'*; do mv -- "$f" "${f//\'/_}"; done 2>/dev/null

	TITLE_GENERATION_CSKEYLIST=$(awk -F "=" '/TITLE_GENERATION_CSKEYLIST=/ {print $2}' $CONFIGFILE) ; TITLE_GENERATION_CSKEYLIST=${TITLE_GENERATION_CSKEYLIST:-"XMP:Title"}
	DESCRIPTION_GENERATION_CSKEYLIST=$(awk -F "=" '/DESCRIPTION_GENERATION_CSKEYLIST=/ {print $2}' $CONFIGFILE) ; DESCRIPTION_GENERATION_CSKEYLIST=${DESCRIPTION_GENERATION_CSKEYLIST:-"XPComment,iptc:Caption-Abstract"}
	OCR_GENERATION_CSKEYLIST=$(awk -F "=" '/OCR_GENERATION_CSKEYLIST=/ {print $2}' $CONFIGFILE) ; OCR_GENERATION_CSKEYLIST=${OCR_GENERATION_CSKEYLIST:-"Keywords,iptc:Keywords"}
	OCR_GENERATION_KEYSEP=$(awk -F "=" '/OCR_GENERATION_KEYSEP=/ {print $2}' $CONFIGFILE) ; OCR_GENERATION_KEYSEP=${OCR_GENERATION_KEYSEP:-","}
	# task of Florence2Run node. One of : more_detailed_caption, detailed_caption, caption 
	DESCRIPTION_FLORENCE_TASK=$(awk -F "=" '/DESCRIPTION_FLORENCE_TASK=/ {print $2}' $CONFIGFILE) ; DESCRIPTION_FLORENCE_TASK=${DESCRIPTION_FLORENCE_TASK:-"more_detailed_caption"}
	DESCRIPTION_LOCALE=$(awk -F "=" '/DESCRIPTION_LOCALE=/ {print $2}' $CONFIGFILE) ; DESCRIPTION_LOCALE=${DESCRIPTION_LOCALE:-""}
	EXIF_PURGE_CSKEYLIST=$(awk -F "=" '/EXIF_PURGE_CSKEYLIST=/ {print $2}' $CONFIGFILE) ; EXIF_PURGE_CSKEYLIST=${EXIF_PURGE_CSKEYLIST:-""}

	uuid=$(openssl rand -hex 16)
	INTERMEDIATEFOLDER_CALL=vr/caption/intermediate/$uuid			# context: output/
	INTERMEDIATEFOLDER=input/$INTERMEDIATEFOLDER_CALL
	mkdir -p $INTERMEDIATEFOLDER
	mkdir -p output/vr/caption/intermediate
	
	COUNT=`find input/vr/caption -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' | wc -l`
	declare -i INDEX=0
	declare -i WAIT=0
	if [[ $COUNT -gt 0 ]] ; then
		VIDEOFILES=`find input/vr/caption -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm'`
		for nextinputfile in $VIDEOFILES ; do
			INDEX+=1
			echo "$INDEX/$COUNT">input/vr/caption/BATCHPROGRESS.TXT
			echo "caption" >user/default/comfyui_stereoscopic/.daemonstatus
			echo "video $INDEX of $COUNT" >>user/default/comfyui_stereoscopic/.daemonstatus
			newfn=${nextinputfile##*/}
			newfn=${newfn//[^[:alnum:].-]/_}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			newfn=$INTERMEDIATEFOLDER/$newfn
			EXTENSION="${newfn##*.}"
			if [ "$EXTENSION" == "mp4" ] ; then
				cp -- "$nextinputfile" $newfn 
			else
				newfn=${newfn%.*}".mp4"
				EXTENSION="${newfn##*.}"
				nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y  -i "$nextinputfile"  $newfn 
			fi
			
			TARGETPREFIX=${newfn##*/}

			echo "$INDEX/$COUNT"": "${newfn##*/}
			
			frame=$INTERMEDIATEFOLDER/frame.png
			nice "$FFMPEGPATHPREFIX"ffmpeg -hide_banner -loglevel error -y  -i "$newfn"  -vf "select=eq(n\,1)" -vframes 1 "$frame"
			
			echo -ne $"\e[91m" ; "$PYTHON_BIN_PATH"python.exe $SCRIPTPATH2  `realpath "$frame"` $DESCRIPTION_FLORENCE_TASK ; echo -ne $"\e[0m"
			
			status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
			if [ "$status" = "closed" ]; then
				echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
				mkdir input/vr/caption/error
				mv -- "$newfn" input/vr/caption/error
				rm -rf $INTERMEDIATEFOLDER
				exit 0
			fi
			
			until [ "$queuecount" = "0" ]
			do
				sleep 1
				curl -silent "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json
				queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
			done				

			WAIT=0
			until [ -e "output/vr/caption/intermediate/temp_caption_short.txt" ] || [ -e "output/vr/caption/intermediate/temp_caption_long.txt" ]  ; do
				WAIT+=1
				echo -ne "$WAIT\r"
				sleep 1
				if [[ $WAIT -ge $CAPTION_TIMEOUT ]] ; then
					echo -e $"\e[91mError:\e[0m ComfyUI prompt is taking to long."
					exit 1
				fi
			done
			sleep 1
			echo "prompt complete."

			if [ ! -e "output/vr/caption/intermediate/temp_caption_short.txt" ] ; then
				cp -v "output/vr/caption/intermediate/temp_caption_long.txt" "output/vr/caption/intermediate/temp_caption_short.txt"
				echo -e $"\e[93mWarning:\e[0m short caption missing - using long caption."
			fi
			if [ ! -e "output/vr/caption/intermediate/temp_caption_long.txt" ] ; then
				cp -v "output/vr/caption/intermediate/temp_caption_short.txt" "output/vr/caption/intermediate/temp_caption_long.txt"
				echo -e $"\e[93mWarning:\e[0m long caption missing - using short caption."
			fi
			if [ ! -e "output/vr/caption/intermediate/temp_ocr.txt" ] ; then
				echo "" >output/vr/caption/intermediate/temp_ocr.txt
				echo -e $"\e[93mWarning:\e[0m ocr missing - ignored."
			fi
			if [ -e "output/vr/caption/intermediate/temp_caption_short.txt" ] && [ -e "output/vr/caption/intermediate/temp_caption_long.txt" ] ; then
				TITLEVAL=`cat output/vr/caption/intermediate/temp_caption_short.txt`
				CAPLONGVAL=`cat output/vr/caption/intermediate/temp_caption_long.txt`
				OCRVAL=
				OCRVAL=`cat output/vr/caption/intermediate/temp_ocr.txt | tr " \t\n" ";"`
				rm -f -- "output/vr/caption/intermediate/temp_caption_short.txt" "output/vr/caption/intermediate/temp_caption_long.txt" "output/vr/caption/intermediate/temp_ocr.txt"  2>/dev/null

				if [ ! -z "$DESCRIPTION_LOCALE" ] && [[ ! "$DESCRIPTION_LOCALE" == "en"* ]] ; then
					echo "translating to $DESCRIPTION_LOCALE ..."
					[ $loglevel -ge 1 ] && echo "TITLEVAL en: $TITLEVAL"
					[ $loglevel -ge 1 ] && echo "CAPLONGVAL en: $CAPLONGVAL"
					TITLEVAL=`"$PYTHON_BIN_PATH"python.exe $SCRIPTPATH3 "$DESCRIPTION_LOCALE" "$TITLEVAL"`
					CAPLONGVAL=`"$PYTHON_BIN_PATH"python.exe $SCRIPTPATH3 "$DESCRIPTION_LOCALE" "$CAPLONGVAL"`
					[ $loglevel -ge 1 ] && echo "TITLEVAL $DESCRIPTION_LOCALE: $TITLEVAL"
					[ $loglevel -ge 1 ] && echo "CAPLONGVAL $DESCRIPTION_LOCALE: $CAPLONGVAL"
				fi
				
				"$EXIFTOOLBINARY" -Keys:all= -overwrite_original "$newfn"
				"$EXIFTOOLBINARY" -L -ItemList:Title= -ItemList:Title="$TITLEVAL" -overwrite_original "$newfn"
				"$EXIFTOOLBINARY" -L -ItemList:Comment= -ItemList:Comment="$CAPLONGVAL" -overwrite_original "$newfn"
				
				mv "$newfn" output/vr/caption
				mkdir -p input/vr/caption/done
				mv -- "$nextinputfile" input/vr/caption/done
				echo -e "$INDEX/$COUNT: "$"\e[92mdone.\e[0m "
				
			else
				echo -e "$INDEX/$COUNT: "$"\e[91mfailed to fetch video result at:\e[0m ""output/vr/caption/intermediate : temp_caption_short.txt , temp_caption_long.txt, temp_ocr.txt""                      "
				ls -la output/vr/caption/intermediate
				mkdir -p input/vr/caption/error
				mv -fv -- "$nextinputfile" input/vr/caption/error
			fi
			
		done
		rm  -f input/vr/caption/BATCHPROGRESS.TXT 
	fi	

	IMGFILES=`find input/vr/caption -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.webp'`
	COUNT=`find input/vr/caption -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.webp' | wc -l`
	INDEX=0
	rm -f intermediateimagefiles.txt
	if [[ $COUNT -gt 0 ]] ; then
		for nextinputfile in $IMGFILES ; do
			if [ ! -e $nextinputfile ] ; then
				echo -e $"\e[91mError:\e[0m File removed. Batch task terminated."
				exit 1
			fi
			INDEX+=1
			echo "$INDEX/$COUNT">input/vr/caption/BATCHPROGRESS.TXT
			echo "caption" >user/default/comfyui_stereoscopic/.daemonstatus
			echo "image $INDEX of $COUNT" >>user/default/comfyui_stereoscopic/.daemonstatus
			newfn=${nextinputfile##*/}
			newfn=${newfn//[^[:alnum:].-]/_}
			newfn=${newfn// /_}
			newfn=${newfn//\(/_}
			newfn=${newfn//\)/_}
			STORENAME=$newfn
			newfn=$INTERMEDIATEFOLDER/$newfn
			cp -- "$nextinputfile" "$newfn"
			
			if [ -e "$newfn" ]; then
				TARGETPREFIX=${newfn##*/}
				TARGETPREFIX=${TARGETPREFIX%.*}
				
				echo "$INDEX/$COUNT"": "${newfn##*/}
				echo -ne $"\e[91m" ; "$PYTHON_BIN_PATH"python.exe $SCRIPTPATH2  `realpath "$newfn"` $DESCRIPTION_FLORENCE_TASK ; echo -ne $"\e[0m"
				
				status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
				if [ "$status" = "closed" ]; then
					echo -e $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT"
					mkdir input/vr/caption/error
					mv -- "$newfn" input/vr/caption/error
					rm -rf $INTERMEDIATEFOLDER
					exit 0
				fi
				
				until [ "$queuecount" = "0" ]
				do
					sleep 1
					curl -silent "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json
					queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
				done				
				
				sync ; sleep 1


				WAIT=0
				until [ -e "output/vr/caption/intermediate/temp_caption_short.txt" ] || [ -e "output/vr/caption/intermediate/temp_caption_long.txt" ]  ; do
					WAIT+=1
					echo -ne "$WAIT\r"
					sleep 1
					if [ $WAIT -ge $CAPTION_TIMEOUT ] ; then
						echo -e $"\e[91mError:\e[0m ComfyUI prompt is taking to long."
						exit 1
					fi
				done
				sleep 1
				echo "prompt complete."
				
				if [ ! -e "output/vr/caption/intermediate/temp_caption_short.txt" ] ; then
					cp -v "output/vr/caption/intermediate/temp_caption_long.txt" "output/vr/caption/intermediate/temp_caption_short.txt"
					echo -e $"\e[93mWarning:\e[0m short caption missing - using long caption."
				fi
				if [ ! -e "output/vr/caption/intermediate/temp_caption_long.txt" ] ; then
					cp -v "output/vr/caption/intermediate/temp_caption_short.txt" "output/vr/caption/intermediate/temp_caption_long.txt"
					echo -e $"\e[93mWarning:\e[0m long caption missing - using short caption."
				fi
				if [ ! -e "output/vr/caption/intermediate/temp_ocr.txt" ] ; then
					echo "" >output/vr/caption/intermediate/temp_ocr.txt
					echo -e $"\e[93mWarning:\e[0m ocr missing - ignored."
				fi
				if [ -e "output/vr/caption/intermediate/temp_caption_short.txt" ] && [ -e "output/vr/caption/intermediate/temp_caption_long.txt" ] ; then
					TITLEVAL=`cat output/vr/caption/intermediate/temp_caption_short.txt`
					CAPLONGVAL=`cat output/vr/caption/intermediate/temp_caption_long.txt`
					OCRVAL=
					OCRVAL=`cat output/vr/caption/intermediate/temp_ocr.txt | tr " \t\n" ";"`
					rm -f -- "output/vr/caption/intermediate/temp_caption_short.txt" "output/vr/caption/intermediate/temp_caption_long.txt" "output/vr/caption/intermediate/temp_ocr.txt" 2>/dev/null
					
					if [ ! -z "$DESCRIPTION_LOCALE" ] &&  [[ ! "$DESCRIPTION_LOCALE" == "en"* ]] ; then
						echo "translating to $DESCRIPTION_LOCALE ..."
						[ $loglevel -ge 1 ] && echo "TITLEVAL en: $TITLEVAL"
						[ $loglevel -ge 1 ] && echo "CAPLONGVAL en: $CAPLONGVAL"
						TITLEVAL=`"$PYTHON_BIN_PATH"python.exe $SCRIPTPATH3 "$DESCRIPTION_LOCALE" "$TITLEVAL"`
						CAPLONGVAL=`"$PYTHON_BIN_PATH"python.exe $SCRIPTPATH3 "$DESCRIPTION_LOCALE" "$CAPLONGVAL"`
						[ $loglevel -ge 1 ] && echo "TITLEVAL $DESCRIPTION_LOCALE: $TITLEVAL"
						[ $loglevel -ge 1 ] && echo "CAPLONGVAL $DESCRIPTION_LOCALE: $CAPLONGVAL"
					fi
					
					#"$EXIFTOOLBINARY" "-""$EXIF_PURGE_OPT""=" -overwrite_original "$newfn"
					for purgekey in $(echo $EXIF_PURGE_CSKEYLIST | sed "s/,/ /g")
					do
						"$EXIFTOOLBINARY"  -$purgekey="" -overwrite_original "$newfn"
					done
					
					for titlekey in $(echo $TITLE_GENERATION_CSKEYLIST | sed "s/,/ /g")
					do
						"$EXIFTOOLBINARY"  -L -$titlekey="$TITLEVAL" -overwrite_original "$newfn"
					done

					for captionkey in $(echo $DESCRIPTION_GENERATION_CSKEYLIST | sed "s/,/ /g")
					do
						"$EXIFTOOLBINARY"  -L -$captionkey="$CAPLONGVAL" -overwrite_original "$newfn"
					done

					for ocrkey in $(echo $OCR_GENERATION_CSKEYLIST | sed "s/,/ /g")
					do
						"$EXIFTOOLBINARY" -$ocrkey="$OCRVAL" -overwrite_original "$newfn"
					done

					mv "$newfn" output/vr/caption
					mkdir -p input/vr/caption/done
					mv -- "$nextinputfile" input/vr/caption/done
					echo -e "$INDEX/$COUNT: "$"\e[92mdone.\e[0m "
					
				else
					echo -e "$INDEX/$COUNT: "$"\e[91mfailed to fetch image result at:\e[0m ""output/vr/caption/intermediate : temp_caption_short.txt , temp_caption_long.txt, temp_ocr.txt""                      "
					ls -la output/vr/caption/intermediate
					mkdir -p input/vr/caption/error
					mv -fv -- "$nextinputfile" input/vr/caption/error
				fi
				
			else
				echo -e $"\e[91mError:\e[0m prompting failed. Missing file: $newfn"
			fi			
		done
		rm  -f input/vr/caption/BATCHPROGRESS.TXT 
				
	fi	
	rm -rf $INTERMEDIATEFOLDER
	echo "Batch done."
fi
exit 0
