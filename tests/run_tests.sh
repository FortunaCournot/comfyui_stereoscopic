#!/bin/sh
# Test installation ...
# Copyright (c) 2025 Fortuna Cournot. MIT License.


# abolute path of ComfyUI folder in your ComfyUI_windows_portable
if [[ "$0" == *"\\"* ]] ; then echo -e $"\e[91m\e[1mCall from Git Bash shell please.\e[0m"; sleep 5; exit; fi
COMFYUIPATH=`realpath $(dirname "$0")/../../..`

cd $COMFYUIPATH

# NON PUBLIC YET
#rm -f -- "custom_nodes/comfyui_stereoscopic/.test/.install" 
#exit
# NON PUBLIC YET

rm -f -- input/vr/scaling/test_image.png input/vr/scaling/done/test_image.png input/vr/scaling/error/test_image.png output/vr/scaling/test_image_x4_4K.png 2>/dev/null
rm -f -- input/vr/scaling/test_video.mp4 input/vr/scaling/done/test_video.mp4 input/vr/scaling/error/test_video.mp4 output/vr/scaling/test_video_x4.mp4 2>/dev/null


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
	echo -e $"\e[91mError:\e[0m All input files must be removed first, then try again."
	echo "Found $COUNT files in incoming folders:"
	echo "$SLIDECOUNT slides , $SCALECOUNT + $OVERRIDECOUNT to scale >> $SBSCOUNT for sbs >> $SINGLELOOPCOUNT to loop, $SLIDECOUNT for slideshow >> $CONCATCOUNT to concat" && echo "$DUBSFXCOUNT to dub, $WMECOUNT to encrypt, $WMDCOUNT to decrypt"
	exit
fi


INTERNAL_VERSION=`cat custom_nodes/comfyui_stereoscopic/.test/.install`
echo "Testing for $INTERNAL_VERSION ..."

echo "#######  1. Scaling  ######"
cp -f ./custom_nodes/comfyui_stereoscopic/tests/input/test_image.png ./input/vr/scaling/
cp -f ./custom_nodes/comfyui_stereoscopic/tests/input/test_video.mp4 ./input/vr/scaling/
./custom_nodes/comfyui_stereoscopic/api/batch_scaling.sh
if [ -e input/vr/scaling/test_video.mp4 ] || [ ! -e input/vr/scaling/done/test_video.mp4 ] || [ ! -e output/vr/scaling/test_video_x4.mp4 ] ; then
	echo -e $"\e[91mTest video scale failed.\e[0m"
	rm -f -- input/vr/scaling/test_video.mp4 input/vr/scaling/done/test_video.mp4 input/vr/scaling/error/test_video.mp4 output/vr/scaling/test_video_x4.mp4 2>/dev/null
	exit
fi
if [ -e input/vr/scaling/test_image.png ] || [ ! -e input/vr/scaling/done/test_image.png ] || [ ! -e output/vr/scaling/test_image_x4_4K.png ] ; then
	echo -e $"\e[91mTest image scale failed.\e[0m"
	rm -f -- input/vr/scaling/test_image.png input/vr/scaling/done/test_image.png input/vr/scaling/error/test_image.png output/vr/scaling/test_image_x4_4K.png 2>/dev/null
	exit
fi
mv -f -- output/vr/scaling/test_image_x4_4K.png output/vr/scaling/test_video_x4.mp4 custom_nodes/comfyui_stereoscopic/.test/$INTERNAL_VERSION  2>/dev/null
rm -f -- input/vr/scaling/test_image.png input/vr/scaling/done/test_image.png output/vr/scaling/test_image_x4_4K.png 2>/dev/null
rm -f -- input/vr/scaling/test_video.mp4 input/vr/scaling/done/test_video.mp4 output/vr/scaling/test_video_x4.mp4 2>/dev/null

rm -f -- "custom_nodes/comfyui_stereoscopic/.test/.install" 
