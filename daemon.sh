#!/bin/sh
# Executes the whole SBS workbench pipeline again and again ...
# Copyright (c) 2025 Fortuna Cournot. MIT License.

# abolute path of ComfyUI folder in your ComfyUI_windows_portable
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../..`

cd $COMFYUIPATH

NOCLEANUP=0
while [ -e user/default/comfyui_stereoscopic/.daemonactive ]; do
    read -p "lock file exists. daemon already active or was killed. Start again? " yn
    case $yn in
        [Yy]* ) break;;
        [Nn]* ) NOCLEANUP=1; exit 0;;
        * ) echo "Please answer yes or no.";;
    esac
done

cleanup() {
	exit_code=$?
	rm -f user/default/comfyui_stereoscopic/.daemonactive
	rm -f user/default/comfyui_stereoscopic/.daemonstatus
	rm -f user/default/comfyui_stereoscopic/.pipelineactive
	#echo "Exit code $exit_code"
	while [[ ${exit_code} -ne 0 ]]; do
		read -p "Error/Interrupt detected. Please press enter to quit: " yn
		case $yn in
			[A-Za-z]* )
				exit_code=0
				break;;
			* )
				echo "Please answer yes or no to quit (no options)."
				break;;
		esac
	done
    exit 0 # exit script after cleanup
}

trap cleanup EXIT

mkdir -p input/vr/slideshow input/vr/dubbing/sfx input/vr/scaling input/vr/fullsbs input/vr/scaling/override input/vr/singleloop input/vr/slides input/vr/concat input/vr/downscale/4K input/vr/caption input/vr/check/rate input/vr/check/released
mkdir -p output/vr/check/rate output/vr/check/released

source ./user/default/comfyui_stereoscopic/.environment
./custom_nodes/comfyui_stereoscopic/api/prerequisites.sh || exit 1


# Use Systempath for python by default, but set it explictly for comfyui portable.
PYTHON_BIN_PATH=
if [ -d "../python_embeded" ]; then
  PYTHON_BIN_PATH=../python_embeded/
fi
mkdir -p user/default/comfyui_stereoscopic
rm -f -- user/default/comfyui_stereoscopic/.daemonstatus 2>/dev/null
touch user/default/comfyui_stereoscopic/.daemonactive
OPENCV_FFMPEG_READ_ATTEMPTS=8192
export OPENCV_FFMPEG_READ_ATTEMPTS
"$PYTHON_BIN_PATH"python.exe ./custom_nodes/comfyui_stereoscopic/gui/python/vrweare.py 2>/dev/null &

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini

SHORT_CONFIGFILE=$CONFIGFILE
CONFIGFILE=`realpath "$CONFIGFILE"`
export CONFIGFILE

loglevel=$(awk -F "=" '/loglevel=/ {print $2}' $CONFIGFILE) ; loglevel=${loglevel:-0}
[ $loglevel -ge 2 ] && set -x

config_version=$(awk -F "=" '/config_version=/ {print $2}' $CONFIGFILE) ; config_version=${config_version:-"-1"}
PIPELINE_AUTOFORWARD=$(awk -F "=" '/PIPELINE_AUTOFORWARD=/ {print $2}' $CONFIGFILE) ; PIPELINE_AUTOFORWARD=${PIPELINE_AUTOFORWARD:-1}
FFMPEGPATHPREFIX=$(awk -F "=" '/FFMPEGPATHPREFIX=/ {print $2}' $CONFIGFILE) ; FFMPEGPATHPREFIX=${FFMPEGPATHPREFIX:-""}
UPSCALEMODELx4=$(awk -F "=" '/UPSCALEMODELx4=/ {print $2}' $CONFIGFILE) ; UPSCALEMODELx4=${UPSCALEMODELx4:-"RealESRGAN_x4plus.pth"}
UPSCALEMODELx2=$(awk -F "=" '/UPSCALEMODELx2=/ {print $2}' $CONFIGFILE) ; UPSCALEMODELx2=${UPSCALEMODELx2:-"RealESRGAN_x4plus.pth"}
FLORENCE2MODEL=$(awk -F "=" '/FLORENCE2MODEL=/ {print $2}' $CONFIGFILE) ; FLORENCE2MODEL=${FLORENCE2MODEL:-"microsoft/Florence-2-base"}
DEPTH_MODEL_CKPT=$(awk -F "=" '/DEPTH_MODEL_CKPT=/ {print $2}' $CONFIGFILE) ; DEPTH_MODEL_CKPT=${DEPTH_MODEL_CKPT:-"depth_anything_v2_vitl.pth"}

TVAI_BIN_DIR=$(awk -F "=" '/TVAI_BIN_DIR=/ {print $2}' $CONFIGFILE | head -n 1) ; TVAI_BIN_DIR=${TVAI_BIN_DIR:-""}
TVAI_MODEL_DATA_DIR=$(awk -F "=" '/TVAI_MODEL_DATA_DIR=/ {print $2}' $CONFIGFILE) ; TVAI_MODEL_DATA_DIR=${TVAI_MODEL_DATA_DIR:-""}
TVAI_MODEL_DIR=$(awk -F "=" '/TVAI_MODEL_DIR=/ {print $2}' $CONFIGFILE) ; TVAI_MODEL_DIR=${TVAI_MODEL_DIR:-""}

CONFIGERROR=

columns=$(tput cols)


if test $# -ne 0
then
	# targetprefix path is relative; parent directories are created as needed
	echo "Usage: $0 "
	echo "E.g.: $0 "
else
	SERVERERROR=
	
	if [ -e custom_nodes/comfyui_stereoscopic/pyproject.toml ]; then
		VERSION=`cat custom_nodes/comfyui_stereoscopic/pyproject.toml | grep "version = " | grep -v "minversion" | grep -v "target-version"`
	else
		echo -e $"\e[91mError:\e[0m script not started in ComfyUI folder!"
		exit
	fi

	### WAIT FOR OLD QUEUE TO FINISH ###
	COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST=/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
	COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT=/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
	status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
	if [ ! "$status" = "closed" ]; then
		curl -silent "http://$COMFYUIHOST:$COMFYUIPORT/prompt" >queuecheck.json
		queuecount=`grep -oP '(?<="queue_remaining": )[^}]*' queuecheck.json`
		[ $loglevel -ge 0 ] && echo "Info: ComfyUI busy. Queuecount: $queuecount"
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
	[ $columns -lt 120 ] &&	CONFIGERROR="x"  && echo -e $"\e[93mWarning:\e[0m Shell windows has less than 120 columns. Go to options - Window and increate it."



	[ $loglevel -ge 0 ] && echo "" 
	./custom_nodes/comfyui_stereoscopic/api/status.sh
	[ $loglevel -ge 0 ] && echo " "
	
	INITIALRUN=TRUE
  TVAIREPORTED=-1
	while true;
	do
		# Check for external soft-kill signal
		if [ ! -e user/default/comfyui_stereoscopic/.daemonactive ]; then
			break
		fi

    # Check availablity of TVAI server
		if [ -e "$TVAI_BIN_DIR" ] && [ -e "$TVAI_MODEL_DIR" ] && [ $TVAIREPORTED -ne 0 ] ; then
      TMP_FILE=$(mktemp)
      curl --ssl-no-revoke -v -s -o - -I https://topazlabs.com/ >/dev/null 2>$TMP_FILE
      HTTP_CODE=`grep "HTTP/1.1 " $TMP_FILE | cut -d ' ' -f3`
      if [ -z "$HTTP_CODE" ] || [ $HTTP_CODE -ge 400 ] ; then
        if [ $TVAIREPORTED -lt 1 ] ; then
          TVAIREPORTED=1
          echo -e $"\e[93mWarning: TVAI server not present ($HTTP_CODE).\e[0m"
          sleep 4
        fi
      else
        if [ $TVAIREPORTED -gt 0 ] ; then
          echo -e $"\e[91mInfo:\e[0m TVAI server present again."
        fi
        TVAIREPORTED=0
      fi
      rm "$TMP_FILE"    
    fi

    # Is there is a limit a TVAI login is valid? Enforce re-login before watermark is applied.
    #if [ -e "$TVAI_MODEL_DIR"/auth.tpz ] && [[ $(find "$TVAI_MODEL_DIR"/auth.tpz -mtime +40 -print) ]]; then
    #  echo "TVAI authentication exists but is older than 40 days - invalidated."
    #  mv -f -- "$TVAI_MODEL_DIR"/auth.tpz "$TVAI_MODEL_DIR"/auth-invalidated.tpz
    #fi

		while [ -e "$TVAI_BIN_DIR" ] && [ -e "$TVAI_MODEL_DIR" ] && [ ! -e "$TVAI_MODEL_DIR"/auth.tpz ]  ; do
			export TVAI_MODEL_DIR
			"$TVAI_BIN_DIR"/login.exe
			read -p "LOGIN, THEN PRESS RETURN TO CONTINUE... " xy
						
			TVAI_BIN_DIR=$(awk -F "=" '/TVAI_BIN_DIR=/ {print $2}' $CONFIGFILE | head -n 1) ; TVAI_BIN_DIR=${TVAI_BIN_DIR:-""}
			TVAI_MODEL_DATA_DIR=$(awk -F "=" '/TVAI_MODEL_DATA_DIR=/ {print $2}' $CONFIGFILE) ; TVAI_MODEL_DATA_DIR=${TVAI_MODEL_DATA_DIR:-""}
			TVAI_MODEL_DIR=$(awk -F "=" '/TVAI_MODEL_DIR=/ {print $2}' $CONFIGFILE) ; TVAI_MODEL_DIR=${TVAI_MODEL_DIR:-""}			
		done
	
		# happens every iteration since daemon is responsibe to initially create config and detect comfyui changes
		COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST=/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
		COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT=/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}
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
			if [ -x "$(command -v nvidia-smi)" ]; then
				DUBSFXCOUNT=`find input/vr/dubbing/sfx -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' | wc -l`
			else
				DUBSFXCOUNT=0
			fi
			SCALECOUNT=`find input/vr/scaling -maxdepth 1 -type f -name '*.mp4' -o -name '*.webp' -o -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
			SBSCOUNT=`find input/vr/fullsbs -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' -o -name '*.webp' -o -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
			OVERRIDECOUNT=`find input/vr/scaling/override -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' -o -name '*.WEBM' -o -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
			SINGLELOOPCOUNT=`find input/vr/singleloop -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' | wc -l`
			INTERPOLATECOUNT=`find input/vr/interpolate -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' | wc -l`
			CONCATCOUNT=`find input/vr/concat -maxdepth 1 -type f -name '*.mp4' | wc -l`
			WMECOUNT=`find input/vr/watermark/encrypt -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
			WMDCOUNT=`find input/vr/watermark/decrypt -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
			CAPCOUNT=`find input/vr/caption -maxdepth 1 -type f -name '*.mp4' -o  -name '*.webm' -o -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.webp' | wc -l`
			TASKCOUNT=`find input/vr/tasks/*/ -maxdepth 1 -type f | wc -l`
			
			if [ $WMECOUNT -gt 0 ] ; then
				WATERMARK_LABEL=$(awk -F "=" '/WATERMARK_LABEL=/ {print $2}' $CONFIGFILE) ; WATERMARK_LABEL=${WATERMARK_LABEL:-""}
				if [[ -z $WATERMARK_LABEL ]] ; then
					echo -e $"\e[93mWarning:\e[0m You must configure WATERMARK_LABEL in $CONFIGFILE to encrypt."
					WMECOUNT=0
				fi
			fi
			
			COUNT=$(( DUBSFXCOUNT + SCALECOUNT + SBSCOUNT + OVERRIDECOUNT + SINGLELOOPCOUNT + INTERPOLATECOUNT + CONCATCOUNT + WMECOUNT + WMDCOUNT + CAPCOUNT + TASKCOUNT ))
			COUNTWSLIDES=$(( SLIDECOUNT + $COUNT ))
			COUNTSBSSLIDES=$(( SLIDESBSCOUNT + $COUNT ))
			if [ -e user/default/comfyui_stereoscopic/.pipelinepause ] ; then
				rm -f user/default/comfyui_stereoscopic/.pipelineactive 2>/dev/null
				BLINK=`shuf -n1 -e "..." "   "`
				[ $loglevel -ge 0 ] && echo -ne $"\e[93m\e[2m*** PAUSED (Use App to resume) *** $BLINK\e[0m \r"
				sleep 1
			elif [[ $COUNT -gt 0 ]] || [[ $SLIDECOUNT -gt 1 ]] || [[ $COUNTSBSSLIDES -gt 1 ]] ; then
				[ $loglevel -ge 0 ] && echo "Found $COUNT files in incoming folders:                               "
				[ $loglevel -ge 0 ] && echo "$SLIDECOUNT slides , $SCALECOUNT + $OVERRIDECOUNT to scale >> $SBSCOUNT for sbs >> $SINGLELOOPCOUNT to loop >> $INTERPOLATECOUNT to interpolate, $SLIDECOUNT for slideshow >> $CONCATCOUNT to concat" && echo "$DUBSFXCOUNT to dub, $WMECOUNT to encrypt, $WMDCOUNT to decrypt, $CAPCOUNT for caption, $TASKCOUNT in tasks"

				touch user/default/comfyui_stereoscopic/.pipelineactive
				sleep 1

        TVAIREPORTED=-1
				./custom_nodes/comfyui_stereoscopic/api/batch_all.sh || exit 1
				[ $loglevel -ge 0 ] && echo "****************************************************"
				[ $loglevel -ge 0 ] && echo "Using ComfyUI on $COMFYUIHOST port $COMFYUIPORT"
				
				./custom_nodes/comfyui_stereoscopic/api/status.sh				
				[ $loglevel -ge 0 ] && echo " "
			else
				BLINK=`shuf -n1 -e "..." "   "`
				[ $loglevel -ge 0 ] && echo -ne $"\e[2mWaiting for new files$BLINK\e[0m                     \r"
				rm -f user/default/comfyui_stereoscopic/.pipelineactive
				sleep 1
			fi
			
			PIPELINE_AUTOFORWARD=$(awk -F "=" '/PIPELINE_AUTOFORWARD=/ {print $2}' $CONFIGFILE) ; PIPELINE_AUTOFORWARD=${PIPELINE_AUTOFORWARD:-1}

			WORKFLOW_FORWARDER_COUNT=`find output/vr/tasks/forwarder -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' -o -name '*.ts' -o -name '*.webp' -o -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
			if [[ $WORKFLOW_FORWARDER_COUNT -gt 0 ]] ; then
				sleep 5
				[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh tasks/forwarder || exit 1 )
			fi
			WORKFLOW_RELEASED_COUNT=`find output/vr/check/released -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' -o -name '*.webp' -o -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
			if [[ $WORKFLOW_RELEASED_COUNT -gt 0 ]] ; then
				sleep 5
				[ $PIPELINE_AUTOFORWARD -ge 1 ] && ( ./custom_nodes/comfyui_stereoscopic/api/forward.sh check/released || exit 1 )
			fi
			
			
		fi
		
	done #KILL ME
fi
[ $loglevel -ge 0 ] && set +x
