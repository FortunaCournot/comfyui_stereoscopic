#!/bin/sh
# Executes the whole SBS workbench pipeline again and again ...
# Copyright (c) 2025 Fortuna Cournot. MIT License.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../..`

cd $COMFYUIPATH

./custom_nodes/comfyui_stereoscopic/api/prerequisites.sh || exit 1

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

SHORT_CONFIGFILE=$CONFIGFILE
CONFIGFILE=`realpath "$CONFIGFILE"`
export CONFIGFILE

loglevel=$(awk -F "=" '/loglevel/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
[ $loglevel -ge 2 ] && set -x

[ $loglevel -ge 0 ] && echo -e $"\e[1mUsing $SHORT_CONFIGFILE\e[0m"
config_version=$(awk -F "=" '/config_version/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
PIPELINE_AUTOFORWARD=$(awk -F "=" '/PIPELINE_AUTOFORWARD/ {print $2}' $CONFIGFILE) ; PIPELINE_AUTOFORWARD=${PIPELINE_AUTOFORWARD:-1}
FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}
UPSCALEMODELx4=$(awk -F "=" '/UPSCALEMODELx4/ {print $2}' $CONFIGFILE) ; UPSCALEMODELx4=${UPSCALEMODELx4:-"RealESRGAN_x4plus.pth"}
UPSCALEMODELx2=$(awk -F "=" '/UPSCALEMODELx2/ {print $2}' $CONFIGFILE) ; UPSCALEMODELx2=${UPSCALEMODELx2:-"RealESRGAN_x4plus.pth"}
FLORENCE2MODEL=$(awk -F "=" '/FLORENCE2MODEL/ {print $2}' $CONFIGFILE) ; FLORENCE2MODEL=${FLORENCE2MODEL:-"microsoft/Florence-2-base"}
DEPTH_MODEL_CKPT=$(awk -F "=" '/DEPTH_MODEL_CKPT/ {print $2}' $CONFIGFILE) ; DEPTH_MODEL_CKPT=${DEPTH_MODEL_CKPT:-"depth_anything_v2_vitl.pth"}

CONFIGERROR=

columns=$(tput cols)


if test $# -ne 0
then
	# targetprefix path is relative; parent directories are created as needed
	echo "Usage: $0 "
	echo "E.g.: $0 "
else
	mkdir -p input/vr/slideshow input/vr/dubbing/sfx input/vr/scaling input/vr/fullsbs input/vr/scaling/override input/vr/singleloop input/vr/slides input/vr/concat input/vr/downscale/4K input/vr/caption
	SERVERERROR=
	
	if [ -e custom_nodes/comfyui_stereoscopic/pyproject.toml ]; then
		VERSION=`cat custom_nodes/comfyui_stereoscopic/pyproject.toml | grep "version = " | grep -v "minversion" | grep -v "target-version"`
	else
		echo -e $"\e[91mError:\e[0m script not started in ComfyUI folder!"
		exit
	fi

	### WAIT FOR OLD QUEUE TO FINISH ###
	COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
	COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
	status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
	if [ ! "$status" = "closed" ]; then
		queuecount=
		until [ "$queuecount" = "0" ]
		do
			sleep 1
			curl -silent "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json
			queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
			[ $loglevel -ge 0 ] && echo -ne "Waiting for old queue to finish. queuecount: $queuecount         \r"
		done
		[ $loglevel -ge 0 ] && echo "                                                             "
		queuecount=
	fi


	### GET READY ... ###
	echo ""
	[ $loglevel -ge 0 ] && echo -e $"\e[97m\e[1mStereoscopic Pipeline Processing started. $VERSION\e[0m"
	[ $loglevel -ge 0 ] && echo -e $"\e[2m"
	[ $loglevel -ge 0 ] && echo "Waiting for your files to be placed in folders:"

	### CHECK FOR OPTIONAL NODE PACKAGES AND OTHER PROBLEMS ###
	if [ ! -d custom_nodes/comfyui-florence2 ]; then
		[ $loglevel -ge 0 ] && echo -e $"\e[93mWarning:\e[0m Custom nodes ComfyUI-Florence2 could not be found. Use Custom Nodes Manager to install v1.0.5."
		CONFIGERROR="x"
	fi
	if [ ! -d custom_nodes/comfyui-mmaudio ] ; then
		[ $loglevel -ge 0 ] && echo -e $"\e[93mWarning:\e[0m Custom nodes ComfyUI-MMAudio could not be found. Use Custom Nodes Manager to install v1.0.2."
		CONFIGERROR="x"
	fi
	[ $columns -lt 120 ] &&	CONFIGERROR="x"  && echo -e $"\e[93mWarning:\e[0m Shell windows has less than 120 columns. Got to options - Window and increate it."



	[ $loglevel -ge 0 ] && echo "" 
	./custom_nodes/comfyui_stereoscopic/api/status.sh
	[ $loglevel -ge 0 ] && echo " "
	
	INITIALRUN=TRUE
	while true;
	do
		# happens every iteration since daemon is responsibe to initially create config and detect comfyui changes
		COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
		COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
		export COMFYUIHOST COMFYUIPORT

		[ $loglevel -ge 0 ] && [[ ! -z "$INITIALRUN" ]] && echo "Using ComfyUI on $COMFYUIHOST port $COMFYUIPORT" && INITIALRUN=

		# GLOBAL: move output to next stage input (This must happen in batch_all per stage, too)
		mkdir -p input/vr/scaling input/vr/fullsbs
		# scaling -> fullsbs
		GLOBIGNORE="*_SBS_LR*.*"
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && mv -f -- output/vr/scaling/*.mp4 output/vr/scaling/*.png output/vr/scaling/*.jpg output/vr/scaling/*.jpeg output/vr/scaling/*.PNG output/vr/scaling/*.JPG output/vr/scaling/*.JPEG input/vr/fullsbs output/vr/scaling/*.webm output/vr/scaling/*.WEBM input/vr/fullsbs  >/dev/null 2>&1
		# slides -> fullsbs
		GLOBIGNORE="*_SBS_LR*.*"
		[ $PIPELINE_AUTOFORWARD -ge 1 ] && mv -f -- output/vr/slides/*.* input/vr/fullsbs  >/dev/null 2>&1
		# dubbing -> scaling
		#GLOBIGNORE="*_x?*.mp4"
		#[ $PIPELINE_AUTOFORWARD -ge 1 ] && mv -f -- output/vr/dubbing/sfx/*.mp4 input/vr/scaling  >/dev/null 2>&1
		
		unset GLOBIGNORE		

		# FAILSAFE
		mv -f -- input/vr/fullsbs/*_SBS_LR*.* output/vr/fullsbs  >/dev/null 2>&1
		
		status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
		if [ "$status" = "closed" ]; then
			echo -ne $"\e[91mError:\e[0m ComfyUI not present. Ensure it is running on $COMFYUIHOST port $COMFYUIPORT\r"
			SERVERERROR="x"
		else
			if [[ ! -z $SERVERERROR ]]; then
				echo ""
				echo -e $"\e[92mComfyUI is serving again.\e[0m"
				SERVERERROR=
			fi
			
			SLIDECOUNT=`find input/vr/slides -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' -o -name '*.webm' -o -name '*.webp' | wc -l`
			SLIDESBSCOUNT=`find input/vr/slideshow -maxdepth 1 -type f -name '*.png' | wc -l`
			DUBSFXCOUNT=`find input/vr/dubbing/sfx -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' | wc -l`
			SCALECOUNT=`find input/vr/scaling -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' -o -name '*.WEBM' -o -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
			SBSCOUNT=`find input/vr/fullsbs -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' -o -name '*.WEBM' -o -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
			OVERRIDECOUNT=`find input/vr/scaling/override -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' -o -name '*.WEBM' -o -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
			SINGLELOOPCOUNT=`find input/vr/singleloop -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' | wc -l`
			CONCATCOUNT=`find input/vr/concat -maxdepth 1 -type f -name '*.mp4' | wc -l`
			WMECOUNT=`find input/vr/watermark/encrypt -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
			WMDCOUNT=`find input/vr/watermark/decrypt -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
			CAPCOUNT=`find input/vr/caption -maxdepth 1 -type f -name '*.mp4' -o  -name '*.webm' -o -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
			TASKCOUNT=`find input/vr/tasks/*/ -maxdepth 1 -type f | wc -l`
			
			if [ $WMECOUNT -gt 0 ] ; then
				WATERMARK_LABEL=$(awk -F "=" '/WATERMARK_LABEL/ {print $2}' $CONFIGFILE) ; WATERMARK_LABEL=${WATERMARK_LABEL:-""}
				if [[ -z $WATERMARK_LABEL ]] ; then
					echo -e $"\e[91mError:\e[0m You must configure WATERMARK_LABEL in $CONFIGFILE to encrypt. exiting."
					exit
				fi
			fi
			
			COUNT=$(( DUBSFXCOUNT + SCALECOUNT + SBSCOUNT + OVERRIDECOUNT + SINGLELOOPCOUNT + CONCATCOUNT + WMECOUNT + WMDCOUNT + CAPCOUNT + TASKCOUNT ))
			COUNTWSLIDES=$(( SLIDECOUNT + $COUNT ))
			COUNTSBSSLIDES=$(( SLIDESBSCOUNT + $COUNT ))
			if [[ $COUNT -gt 0 ]] || [[ $SLIDECOUNT -gt 1 ]] || [[ $COUNTSBSSLIDES -gt 1 ]] ; then
				[ $loglevel -ge 0 ] && echo "Found $COUNT files in incoming folders:"
				[ $loglevel -ge 0 ] && echo "$SLIDECOUNT slides , $SCALECOUNT + $OVERRIDECOUNT to scale >> $SBSCOUNT for sbs >> $SINGLELOOPCOUNT to loop, $SLIDECOUNT for slideshow >> $CONCATCOUNT to concat" && echo "$DUBSFXCOUNT to dub, $WMECOUNT to encrypt, $WMDCOUNT to decrypt, $CAPCOUNT for caption, $TASKCOUNT in tasks"
				sleep 1
				./custom_nodes/comfyui_stereoscopic/api/batch_all.sh || exit 1
				[ $loglevel -ge 0 ] && echo "****************************************************"
				[ $loglevel -ge 0 ] && echo "Using ComfyUI on $COMFYUIHOST port $COMFYUIPORT"
				
				./custom_nodes/comfyui_stereoscopic/api/status.sh				
				[ $loglevel -ge 0 ] && echo " "
			else
				BLINK=`shuf -n1 -e "..." "   "`
				[ $loglevel -ge 0 ] && echo -ne $"\e[2mWaiting for new files$BLINK\e[0m     \r"
				sleep 1
			fi
		fi
		
		DOWNSCALECOUNT=`find input/vr/downscale/4K -maxdepth 1 -type f -name '*.mp4' | wc -l`
		if [[ $DOWNSCALECOUNT -gt 0 ]]; then
			./custom_nodes/comfyui_stereoscopic/api/batch_downscale.sh || exit 1
		fi

	done #KILL ME
fi
[ $loglevel -ge 0 ] && set +x
