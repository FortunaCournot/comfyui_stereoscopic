# comfyui_stereoscopic
ComfyUI Custom Nodes to create stereoscopic images and movies.

This package is based on some code of Sam Seen from https://github.com/MrSamSeen/ComfyUI_SSStereoscope

## Node "SBS Converter"
This node converts an image to a side-by-side image.

### Parameters

#### depth_scale
The depth scale is normalized. 1.0 is the normal value, 0.0 means no scale, higher values generate stronger effects.

#### depth_offset
The depth scale is normalized. 0.0 is half to front, half to back. Value equal to depth_scale is full to front, negative values shift it to the back.

#### switch_sides
Switch left/right. 

#### blur_radius
blur kernel size dimension. -1 turns blurring off.

#### symetric
if true the shift is equally devided to left and right. if false, only one image is effected.

#### processing
Normal. Other values are for development tests and not going to be documented.




