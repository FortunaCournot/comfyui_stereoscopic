#!/bin/sh
# Test installation ...
# Copyright (c) 2025 Fortuna Cournot. MIT License.


# abolute path of ComfyUI folder in your ComfyUI_windows_portable
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`

cd $COMFYUIPATH

echo "Test starting..." >custom_nodes/comfyui_stereoscopic/.test/errorlog.txt

CONFIGFILE=./user/default/comfyui_stereoscopic/config.ini
SHORT_CONFIGFILE=$CONFIGFILE
CONFIGFILE=`realpath "$CONFIGFILE"`
export CONFIGFILE
COMFYUIHOST=$(awk -F "=" '/COMFYUIHOST=/ {print $2}' $CONFIGFILE) ; COMFYUIHOST=${COMFYUIHOST:-"127.0.0.1"}
COMFYUIPORT=$(awk -F "=" '/COMFYUIPORT=/ {print $2}' $CONFIGFILE) ; COMFYUIPORT=${COMFYUIPORT:-"8188"}

find ./input/vr -name test_* -exec rm -rf -- {} \;  2>/dev/null
find ./output/vr -name test_* -exec rm -rf -- {} \;  2>/dev/null

SLIDECOUNT=`find input/vr/slides -maxdepth 1 -type f -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' -o -name '*.webm' -o -name '*.WEBM' | wc -l`
SLIDESBSCOUNT=`find input/vr/slideshow -maxdepth 1 -type f -name '*.png' | wc -l`
DUBSFXCOUNT=`find input/vr/dubbing/sfx -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' | wc -l`
SCALECOUNT=`find input/vr/scaling -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' -o -name '*.WEBM' -o -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
SBSCOUNT=`find input/vr/fullsbs -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' -o -name '*.WEBM' -o -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
OVERRIDECOUNT=`find input/vr/scaling/override -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' -o -name '*.WEBM' -o -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
SINGLELOOPCOUNT=`find input/vr/singleloop -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' | wc -l`
CONCATCOUNT=`find input/vr/concat -maxdepth 1 -type f -name '*.mp4' | wc -l`
WMECOUNT=`find input/vr/watermark/encrypt -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' -o -name '*.WEBM' -o -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`
WMDCOUNT=`find input/vr/watermark/decrypt -maxdepth 1 -type f -name '*.mp4' -o -name '*.webm' -o -name '*.WEBM' -o -name '*.png' -o -name '*.PNG' -o -name '*.jpg' -o -name '*.JPG' -o -name '*.jpeg' -o -name '*.JPEG' | wc -l`

COUNT=$(( DUBSFXCOUNT + SCALECOUNT + SBSCOUNT + OVERRIDECOUNT + SINGLELOOPCOUNT + CONCATCOUNT + WMECOUNT + WMDCOUNT ))
if [[ $COUNT -gt 0 ]] || [[ $SLIDECOUNT -gt 0 ]] || [[ $SLIDESBSCOUNT -gt 0 ]] ; then
	echo -e $"\e[91mError:\e[0m All input files must be removed fot tests first, then try again."
	echo "Found $COUNT files in incoming folders:"
	echo "$SLIDECOUNT slides , $SCALECOUNT + $OVERRIDECOUNT to scale >> $SBSCOUNT for sbs >> $SINGLELOOPCOUNT to loop, $SLIDECOUNT for slideshow >> $CONCATCOUNT to concat" && echo "$DUBSFXCOUNT to dub, $WMECOUNT to encrypt, $WMDCOUNT to decrypt"
	echo "Error: All input files must be removed fot tests." >custom_nodes/comfyui_stereoscopic/.test/errorlog.txt
	exit 1
fi


INTERNAL_VERSION=`cat custom_nodes/comfyui_stereoscopic/.test/.install`
TESTCOUNT=2
echo -e $"\e[96m******* RUNNING TESTS FOR $INTERNAL_VERSION ... *******\e[0m"
echo ""

status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
if [ "$status" = "closed" ]; then
  echo "Waiting for ComfyUI to start on http://""$COMFYUIHOST"":""$COMFYUIPORT ..."
  while [ "$status" = "closed" ]; do
    sleep 1
    status=`true &>/dev/null </dev/tcp/$COMFYUIHOST/$COMFYUIPORT && echo open || echo closed`
  done
fi
echo ""
echo "ComfyUI is present."

#### SKIP FOR RUNNER
if [ -e "custom_nodes/comfyui_stereoscopic/.test/.install.log" ] ; then
	echo Skip tests in runner
	rm custom_nodes/comfyui_stereoscopic/.test/.install
	# stdbuf -oL -eL ./custom_nodes/comfyui_stereoscopic/tests/run_tests.sh >> "custom_nodes/comfyui_stereoscopic/.test/.install.log" || exit 1
fi


echo -e $"####### \e[96mTest 1/$TESTCOUNT: SBS converter\e[0m ######"
rm -f -- input/vr/fullsbs/test_image.png input/vr/fullsbs/done/test_image.png input/vr/fullsbs/error/test_image.png output/vr/fullsbs/test_image_x4_4K.png 2>/dev/null
rm -f -- input/vr/fullsbs/test_video.mp4 input/vr/fullsbs/done/test_video.mp4 input/vr/fullsbs/error/test_video.mp4 output/vr/fullsbs/test_video_x4.mp4 2>/dev/null
cp -f ./custom_nodes/comfyui_stereoscopic/tests/input/test_image.png ./input/vr/fullsbs
cp -f ./custom_nodes/comfyui_stereoscopic/tests/input/test_video.mp4 ./input/vr/fullsbs
./custom_nodes/comfyui_stereoscopic/api/batch_sbsconverter.sh 1.0 0.0
if [ -e input/vr/fullsbs/test_video.mp4 ] || [ ! -e input/vr/fullsbs/done/test_video.mp4 ] || [ ! -e output/vr/fullsbs/test_video_SBS_LR.mp4 ] ; then
	echo -e $"\e[91mTest video sbs converter failed.\e[0m"
	echo -e $"\e[91mTo skip tests, manually delete file '.install' in folder \e[96m./custom_nodes/comfyui_stereoscopic/.test\e[0m"
	echo "Error: Test video sbs converter failed." >custom_nodes/comfyui_stereoscopic/.test/errorlog.txt
	exit 1
fi
if [ -e input/vr/fullsbs/test_image.png ] || [ ! -e input/vr/fullsbs/done/test_image.png ] || [ ! -e output/vr/fullsbs/test_image_SBS_LR.png ] ; then
	echo -e $"\e[91mTest image sbs converter failed.\e[0m"
	echo -e $"\e[91mTo skip tests, manually delete file '.install' in folder \e[96m./custom_nodes/comfyui_stereoscopic/.test\e[0m"
	echo "Error: Test image sbs converter failed." >custom_nodes/comfyui_stereoscopic/.test/errorlog.txt
	exit 1
fi
mv -f -- output/vr/fullsbs/test_image_SBS_LR.png output/vr/fullsbs/test_video_SBS_LR.mp4 custom_nodes/comfyui_stereoscopic/.test/$INTERNAL_VERSION  2>/dev/null
rm -f -- input/vr/fullsbs/test_image.png input/vr/fullsbs/done/test_image.png output/vr/fullsbs/test_image_SBS_LR.png 2>/dev/null
rm -f -- input/vr/fullsbs/test_video.mp4 input/vr/fullsbs/done/test_video.mp4 output/vr/fullsbs/test_video_SBS_LR.mp4 2>/dev/null
echo -e $"####### \e[92mTEST STEP SUCCEEDED\e[0m ######"
echo " "

echo -e $"####### \e[96mTest 2/$TESTCOUNT: Scaling\e[0m ######"
	rm -f -- input/vr/scaling/test_video.mp4 input/vr/scaling/done/test_video.mp4 input/vr/scaling/error/test_video.mp4 output/vr/scaling/test_video_x4.mp4 2>/dev/null
	rm -f -- input/vr/scaling/test_image.png input/vr/scaling/done/test_image.png input/vr/scaling/error/test_image.png output/vr/scaling/test_image_x4_4K.png 2>/dev/null
cp -f ./custom_nodes/comfyui_stereoscopic/tests/input/test_image.png ./input/vr/scaling
cp -f ./custom_nodes/comfyui_stereoscopic/tests/input/test_video.mp4 ./input/vr/scaling
./custom_nodes/comfyui_stereoscopic/api/batch_scaling.sh
if [ -e input/vr/scaling/test_video.mp4 ] || [ ! -e input/vr/scaling/done/test_video.mp4 ] || [ ! -e output/vr/scaling/test_video_x4.mp4 ] ; then
	echo -e $"\e[91mTest video scale failed.\e[0m"
	echo -e $"\e[91mTo skip tests, manually delete file '.install' in folder \e[96m./custom_nodes/comfyui_stereoscopic/.test\e[0m"
	echo "Error: Test video scale failed." >custom_nodes/comfyui_stereoscopic/.test/errorlog.txt
	exit 1
fi
if [ -e input/vr/scaling/test_image.png ] || [ ! -e input/vr/scaling/done/test_image.png ] || [ ! -e output/vr/scaling/test_image_x4_4K.png ] ; then
	echo -e $"\e[91mTest image scale failed.\e[0m"
	echo -e $"\e[91mTo skip tests, manually delete file '.install' in folder \e[96m./custom_nodes/comfyui_stereoscopic/.test\e[0m"
	echo "Error: Test image scale failed." >custom_nodes/comfyui_stereoscopic/.test/errorlog.txt
	exit 1
fi
mv -f -- output/vr/scaling/test_image_x4_4K.png output/vr/scaling/test_video_x4.mp4 custom_nodes/comfyui_stereoscopic/.test/$INTERNAL_VERSION  2>/dev/null
rm -f -- input/vr/scaling/test_image.png input/vr/scaling/done/test_image.png output/vr/scaling/test_image_x4_4K.png 2>/dev/null
rm -f -- input/vr/scaling/test_video.mp4 input/vr/scaling/done/test_video.mp4 output/vr/scaling/test_video_x4.mp4 2>/dev/null
echo -e $"####### \e[92mTEST STEP SUCCEEDED\e[0m ######"
echo " "

echo -e $"\e[92m####### ALL TESTS SUCCEEDED ######\e[0m"
rm -f -- "custom_nodes/comfyui_stereoscopic/.test/.install" 
echo "Tests successful." >custom_nodes/comfyui_stereoscopic/.test/errorlog.txt
exit 0
