import torch
from PIL import Image
import os
import sys
import cv2
import math
from comfy.utils import ProgressBar
from datetime import datetime

import numpy # Sometimes we want to use a numpy function even if CuPy is available

_USE_GPU = False
#try:
#    import cupy as np
#    import cupyx.scipy.ndimage
#    _USE_GPU = True
#except ModuleNotFoundError:
import numpy as np
#    print("CuPy not available, only use_gpu=False will work")
    
def gpu_blur(input_array, blur_radius):

    if _USE_GPU:
        # gaussian_filter radius := round(truncate * sigma) will be used. Truncate default = 4.0.
        blurred = cupyx.scipy.ndimage.gaussian_filter(input_array, blur_radius / 4.0)
    else:
        gpu_mat = cv2.UMat(input_array)
        kernel_size = (blur_radius, blur_radius)
        smoothed_gpu = cv2.blur(gpu_mat, kernel_size)
        blurred = cv2.UMat.get(smoothed_gpu)
    return blurred

def invert_map(F, iterations, processing):
    """
    Performs mapping of pixel locations from image source to destination system.
    Source and discussion of the algorithm:
    https://stackoverflow.com/questions/41703210/inverting-a-real-valued-index-grid/78950229#78950229

    F: shifted coordinates (pixel locations) defined in image source system

    Returns shifted coordinates (pixel locations) solved to representation in image destination system.
    """

    if processing == "display-values":
        start_time = datetime.now()

    # shape is (h, w, 2), an "xymap"
    (h, w) = F.shape[:2]
    I = np.zeros_like(F)
    I[:,:,1], I[:,:,0] = np.indices((h, w)) # identity map
    if _USE_GPU:
        I = np.asnumpy(I)
        src=np.asnumpy(F)
    else:
        src=F
    P = np.copy(I)
    for i in range(iterations):
        correction = I - cv2.remap(src, P, None, interpolation=cv2.INTER_LINEAR)
        P += correction * 0.5
        
    if processing == "display-values":
        time_elapsed = datetime.now() - start_time
        print('[comfyui_stereoscopic] (invert_map) Time elapsed (hh:mm:ss.ms) {}'.format(time_elapsed))
        
    return P

def invert_map_1d_monotonic(pixel_shifts_in, processing):
    """
    Inverse map for 1D horizontal shift without iterations.
    Input:
        pixel_shifts_in: (H, W) float32 — rightward shift for each pixel in the SOURCE image.
    Output:
        P: (H, W, 2) float32 — source coordinate map for each target pixel (as used in OpenCV remap).
        P[...,0] — x-coordinate in the source; P[...,1] — y-coordinate in the source (just the row index).
    """

    if processing == "display-values":
        start_time = datetime.now()

    H, W = pixel_shifts_in.shape
    x = np.arange(W, dtype=np.float32)
    P = np.zeros((H, W, 2), dtype=np.float32)
    P[...,1] = np.arange(H, dtype=np.float32)[:, None]

    for y in range(H):
        s = pixel_shifts_in[y]     # (W,)
        u = x - s                  # source → receiver
        u_mono = numpy.maximum.accumulate(u)  # guarantee monotony
        t = x                      # uniform receiver grid
        P[y, :, 0] = np.interp(t, u_mono, x, left=0.0, right=W-1)

    if processing == "display-values":
        time_elapsed = datetime.now() - start_time
        print('[comfyui_stereoscopic] (invert_map_1d_monotonic) Time elapsed (hh:mm:ss.ms) {}'.format(time_elapsed))

    return P
    
def apply_subpixel_shift(image, pixel_shifts_in, flip_offset, iterations, processing, displaytext):
    """
    Performs a subpixel shift of the image depending on the shift map

    image: original image (H, W, 3), uint8
    pixel_shifts: shift map (H, W), float32
    flip_offset: 0 (parallel) or width (cross-eyed)

    Returns the left stereo frame.
    """
    H, W, _ = image.shape

    if processing == "display-values":
        start_time = datetime.now()

    # Create a coordinate grid
    x_coords, y_coords = np.meshgrid(np.arange(W), np.arange(H))

    if processing == "display-values":
        time_elapsed = datetime.now() - start_time
        print('[comfyui_stereoscopic] (create grid) Time elapsed (hh:mm:ss.ms) {}'.format(time_elapsed))

    #prepare remap by inverting shift towards destination space:
    P = invert_map_1d_monotonic(pixel_shifts_in.astype(np.float32), processing)
    pixel_shifts = x_coords - P[..., 0]
    
    #F = np.zeros((H, W, 2), dtype=np.float32)
    #F[..., 0] = np.clip(x_coords - pixel_shifts_in, 0, W-1)
    #F[..., 1] = y_coords
    #P = invert_map(F, iterations, processing)
    #x_coords = np.asnumpy(x_coords)
    #if _USE_GPU:
    #    x_coords = np.asnumpy(x_coords)
    #pixel_shifts = x_coords - P[..., 0]


    if processing == "display-values":
        start_time = datetime.now()
    
    # Apply shift to x-coordinates
    shifted_x = x_coords - pixel_shifts  # left shift for left eye
    shifted_x = np.clip(shifted_x, 0, W - 1).astype(np.float32)
    y_coords = y_coords.astype(np.float32)

    if processing == "display-values":
        time_elapsed = datetime.now() - start_time
        print('[comfyui_stereoscopic] (apply shift) Time elapsed (hh:mm:ss.ms) {}'.format(time_elapsed))

    if processing == "display-values":
        start_time = datetime.now()

    # Placement in the left half
    sbs_result = np.zeros((H, W * 2, 3), dtype=np.uint8)
    #aimask_img = np.zeros((H, W, 3), dtype=np.uint8)

    if processing == "test-pixelshifts-x8":
        #print(f"test-pixelshifts-x8 exit called...")
        pixel_shifts_x8 = pixel_shifts * 8
        if _USE_GPU:
            sbs_result = np.asnumpy(sbs_result)
        sbs_result[:, flip_offset:flip_offset+W,0] = numpy.clip(pixel_shifts_x8, 0, 255).astype(np.uint8)
        sbs_result[:, flip_offset:flip_offset+W,1] = numpy.clip(-pixel_shifts_x8, 0, 255).astype(np.uint8)
        sbs_result[:, flip_offset:flip_offset+W,2] = numpy.clip(0, 0, 255).astype(np.uint8)
        #print(f"test-appliedshifts-x8 processed: {sbs_result.shape}")
        return sbs_result

    if processing == "display-values":
        time_elapsed = datetime.now() - start_time
        print('[comfyui_stereoscopic] (other preparations) Time elapsed (hh:mm:ss.ms) {}'.format(time_elapsed))
        
    # monotony per line (purly related to depth scale)
    #if processing == "display-values":
    #    start_time = datetime.now()
    #shifted_x = numpy.maximum.accumulate(shifted_x, axis=1)
    #if processing == "display-values":
    #    time_elapsed = datetime.now() - start_time
    #    print('[comfyui_stereoscopic] (monotony per line) Time elapsed (hh:mm:ss.ms) {}'.format(time_elapsed))

    # Interpolation with remap
    if processing == "display-values":
        start_time = datetime.now()
    if _USE_GPU:
        y_coords = np.asnumpy(y_coords)
    shifted_img = cv2.remap(image, shifted_x, y_coords, interpolation=cv2.INTER_LINEAR,borderMode=cv2.BORDER_REFLECT)
    if processing == "display-values":
        time_elapsed = datetime.now() - start_time
        print('[comfyui_stereoscopic] (interpolation) Time elapsed (hh:mm:ss.ms) {}'.format(time_elapsed))

    if processing == "display-values":
        start_time = datetime.now()

    if _USE_GPU:
        sbs_result = np.asnumpy(sbs_result) 

    if processing == "pixel-shift-x8":   
        pixel_shifts_x2 = pixel_shifts * 8
        sbs_result[:, flip_offset:flip_offset+W,0] = np.clip(pixel_shifts_x2, 0, 255).astype(np.uint8)
        sbs_result[:, flip_offset:flip_offset+W,1] = np.clip(pixel_shifts_x2, 0, 255).astype(np.uint8)
        sbs_result[:, flip_offset:flip_offset+W,2] = np.clip(pixel_shifts_x2, 0, 255).astype(np.uint8)
    elif processing == "test-shift-grid":
        # draw vertical lines
        step=10
        z=0
        for x in numpy.linspace(start=0, stop=W-1, num=int(W/step)):
            x = int(round(x))
            for y in numpy.linspace(start=step, stop=H-1, num=int(H/step)):
                cv2.line(image, (int(round(x)), int(round(y-step))), (int(round(x)), int(round(y))), color=(255-int(255*z), int(255*z), 128), thickness=1)
                z=1-z
        # draw horizontal lines
        for y in numpy.linspace(start=0, stop=H-1, num=int(H/step)):
            y = int(round(y))
            for x in numpy.linspace(start=step, stop=W-1, num=int(W/step)):
                cv2.line(image, (int(round((x-step))), int(round(y))), (int(round(x)), int(round(y))), color=(0, int(255*z), 255-int(255*z)), thickness=1)
                z=1-z
        shifted_img = cv2.remap(image, shifted_x, y_coords, interpolation=cv2.INTER_LINEAR,borderMode=cv2.BORDER_REFLECT)
        sbs_result[:, flip_offset:flip_offset+W] = shifted_img
    else:
        # Placement in the left half
        sbs_result[:, flip_offset:flip_offset+W] = shifted_img

    if processing != "Normal":          
        font = cv2.FONT_HERSHEY_SIMPLEX
        org = (flip_offset+10, H-10)
        fontScale = 1
        color = (255, 192, 192)
        thickness = 2 
        image = cv2.putText(sbs_result, displaytext, org, font, fontScale, color, thickness, cv2.LINE_AA)

    if processing == "display-values":
        time_elapsed = datetime.now() - start_time
        print('[comfyui_stereoscopic] (finishing) Time elapsed (hh:mm:ss.ms) {}'.format(time_elapsed))

    return sbs_result


class ImageVRConverter:
    #def __init__(self):
    #    self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    #    self.depth_model = None
    #    self.original_depths = []

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "base_image": ("IMAGE",),
                "depth_image": ("IMAGE",),
                "depth_scale": ("FLOAT", {"default": 1.0, "min": 0.0, "max": 10.0, "step": 0.1}),
                "depth_offset": ("FLOAT", {"default": 0.0, "min": -10.0, "max": 10.0, "step": 0.1}),
                "switch_sides": ("BOOLEAN", {"default": False}),
                "blur_radius": ("INT", {"default": 45, "min": -1, "max": 99, "step": 2}),
                "symetric": ("BOOLEAN", {"default": True}),
#                "iterations": ("INT", {"default": 1, "min": 1, "max": 10, "step": 1}),
                "processing": (["Normal", "test-pixelshifts-x8",  "test-blackout", "test-shift-grid", "display-values"], {"default": "Normal"}),
            }
        }

    RETURN_TYPES = ("IMAGE", )
    RETURN_NAMES = ("stereoscopic_image", )
    FUNCTION = "process"
    CATEGORY = "Stereoscopic"
    DESCRIPTION = "Create stereoscopic image with automatic shift from depth map. For VR headsets and 3D displays."


    def process(self, base_image, depth_image, depth_scale, depth_offset, switch_sides,
        blur_radius, symetric, processing
        ):
        """
        Convert image to a side-by-side (SBS) stereoscopic image using a provided depth map.

        Returns:
        - sbs_image: the stereoscopic image(s).
        """

        iterations = 1  # turned off - from old code
        
        if processing == "display-values":
            start_time = datetime.now()

        #define constant
        mode="Parallel"
        invert_depth=True  # The use of depth anything as depth generator requires this.
        
        # Get batch size
        B = base_image.shape[0]

        # Process each image in the batch
        sbs_images = []

        for b in range(B):

            if processing == "display-values":
                start_time2 = datetime.now()

            # Get the current image from the batch
            current_image = base_image[b].cpu().numpy()  # Get image b from batch
            current_image_pil = Image.fromarray((current_image * 255).astype(np.uint8))  # Convert to PIL
            current_depth_image = depth_image[b].cpu().numpy()  # Get depth_image b from batch

            depth_for_sbs = current_depth_image
            if len(depth_for_sbs.shape) == 3 and depth_for_sbs.shape[2] == 3:
                depth_for_sbs = depth_for_sbs[:, :, 0].copy()  # Use red channel
            else:
                depth_for_sbs = depth_for_sbs.copy()

            # Invert depth if requested (swap foreground/background)
            if invert_depth:
                #print("Inverting depth map (swapping foreground/background)")
                depth_for_sbs = 1.0 - depth_for_sbs

            # Get the dimensions of the original img
            width, height = current_image_pil.size

            # Convert depth_for_sbs to 8-bit PIL image and resize
            depth_map_img = Image.fromarray((depth_for_sbs * 255).astype(np.uint8))
            depth_map_img = depth_map_img.resize((width, height), Image.NEAREST)

            # Calculate the shift matrix (pixel_shifts)
            depth_np      = np.array(depth_map_img, dtype=np.float32) - 128.0


            # Preparing the source image in NumPy [0–255] and create a "canvas" for the SBS image twice as wide
            current_image_np = (current_image * 255).astype(np.uint8)
            sbs_image = np.zeros((height, width * 2, 3), dtype=np.uint8)
            shifted_aimask_image = np.zeros((height, width * 2, 3), dtype=np.uint8)

            # Duplicate the source into both halves
            if _USE_GPU:
                if mode == "Parallel":
                    sbs_image[:, width:]  = np.asarray(current_image_np)
                else:
                    sbs_image[:, :width]  = np.asarray(current_image_np)
            else:
                if mode == "Parallel":
                    sbs_image[:, width:]  = current_image_np
                else:
                    sbs_image[:, :width]  = current_image_np


            # Define the viewing mode (parallel, cross)
            fliped = 0 if mode == "Parallel" else width
            
            displaytext = 'depth_scale ' + str(depth_scale) + ', depth_offset = ' + str(depth_offset)
            
            depth_scale_local = 0.2 # magic
            depth_offset_local = depth_offset * - 24.0 # magic 

            if symetric:
                depth_scale_local = depth_scale_local / 2.0
                depth_offset_local = depth_offset_local / 2.0
            if invert_depth:
                depth_offset_local = -depth_offset_local            
            crop_size = int (depth_scale * 6)
            crop_size = crop_size + int (depth_offset * 8)
            if symetric:
                crop_size = int(crop_size / 2)
                crop_size2 = int (depth_scale * 6)
                crop_size2 = crop_size2 - int (depth_offset * 8)
                crop_size2 = int(crop_size2 / 2)
            
            if processing == "display-values":
                time_elapsed = datetime.now() - start_time2
                print('[comfyui_stereoscopic] (initialization) Time elapsed (hh:mm:ss.ms) {}'.format(time_elapsed))
            
            pixel_shifts = (depth_np * depth_scale_local + depth_offset_local).astype(np.float32)# np.int32 to np.float32     

            if processing == "display-values":
                start_time2 = datetime.now()
            if blur_radius>0:
                pixel_shifts = gpu_blur(pixel_shifts,blur_radius)
            if processing == "display-values":
                time_elapsed = datetime.now() - start_time2
                print('[comfyui_stereoscopic] (blur) Time elapsed (hh:mm:ss.ms) {}'.format(time_elapsed))
                
            shifted_half = apply_subpixel_shift(current_image_np, pixel_shifts, fliped, iterations, processing, displaytext)                
            if _USE_GPU:
                sbs_image = np.asnumpy(sbs_image) 
            sbs_image[:, fliped:fliped + width] = shifted_half[:, fliped:fliped + width]

            if symetric:
                fliped = width - fliped
                pixel_shifts = (depth_np * -depth_scale_local + depth_offset_local).astype(np.float32)# np.int32 to np.float32     
                
                if processing == "display-values":
                    start_time2 = datetime.now()               
                if blur_radius>0:
                    pixel_shifts = gpu_blur(pixel_shifts,blur_radius)
                if processing == "display-values":
                    time_elapsed = datetime.now() - start_time2
                    print('[comfyui_stereoscopic] (blur) Time elapsed (hh:mm:ss.ms) {}'.format(time_elapsed))
                    
                shifted_half = apply_subpixel_shift(current_image_np, pixel_shifts, fliped, iterations, processing, displaytext)                
                sbs_image[:, fliped:fliped + width] = shifted_half[:, fliped:fliped + width]
                
                fliped = width - fliped

            #Blackout parts without sufficient information
            if processing != "test-shift-grid" and processing != "display-values":
                fillcolor=(0, 0, 0)
                thickness = -1
                if processing == "test-blackout": 
                    fillcolor=(255, 0, 0)
                    thickness = 1
                if crop_size>0:
                    cv2.rectangle(sbs_image, (width - crop_size, 0), (width - 1, height - 1), fillcolor, thickness)
                elif crop_size<0:
                    cv2.rectangle(sbs_image, (0, 0), (-crop_size - 1, height - 1), fillcolor, thickness)
                if symetric:
                    if crop_size2>0:
                        cv2.rectangle(sbs_image, (width, 0), (width+crop_size2, height - 1), fillcolor, thickness)
                    elif crop_size2<0:
                        cv2.rectangle(sbs_image, (2*width+crop_size2, 0), (2*width -1, height - 1), fillcolor, thickness)
                #else:
                #    crop_size=-crop_size
                #    if crop_size>0:
                #        cv2.rectangle(sbs_image, (width - crop_size, 0), (width - 1, height - 1), fillcolor, thickness)
                #    elif crop_size<0:
                #        cv2.rectangle(sbs_image, (0, 0), (-crop_size - 1, height - 1), fillcolor, thickness)
            if switch_sides:
                sbs_image_swapped = np.zeros((height, width * 2, 3), dtype=np.uint8)
                sbs_image_swapped[:, 0: width] = sbs_image[:, width : width + width]
                sbs_image_swapped[:, width : width + width] = sbs_image[:, 0: width]
                sbs_image = sbs_image_swapped

            # Convert to tensor
            sbs_image_tensor = torch.tensor(sbs_image.astype(np.float32) / 255.0)
            # Add to our batch lists
            sbs_images.append(sbs_image_tensor)
            
        # Stack the results to create batched tensors
        sbs_images_batch = torch.stack(sbs_images)
 
        if processing == "display-values":
            time_elapsed = datetime.now() - start_time
            print('[comfyui_stereoscopic] Time elapsed (hh:mm:ss.ms) {}'.format(time_elapsed))
 
        return (sbs_images_batch, )
