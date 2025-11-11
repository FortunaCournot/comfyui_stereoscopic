import numpy as np
import os
import cv2
import time
from numba import njit

def cpu_blur(input_array, blur_radius):

    kernel_size = (blur_radius, blur_radius)
    blurred = cv2.blur(input_array, kernel_size)
    return blurred

def invert_map_1d_monotonic(pixel_shifts_in):
    """
    Inverse map for 1D horizontal shift without iterations.
    Input:
        pixel_shifts_in: (H, W) float32 — rightward shift for each pixel in the SOURCE image.
    Output:
        P: (H, W, 2) float32 — source coordinate map for each target pixel (as used in OpenCV remap).
        P[...,0] — x-coordinate in the source; P[...,1] — y-coordinate in the source (just the row index).
    """
    H, W = pixel_shifts_in.shape
    x = np.arange(W, dtype=np.float32)
    P = np.zeros((H, W, 2), dtype=np.float32)
    P[...,1] = np.arange(H, dtype=np.float32)[:, None]

    for y in range(H):
        s = pixel_shifts_in[y]     # (W,)
        u = x - s                  # source → receiver
        u_mono = np.maximum.accumulate(u)  # guarantee monotony
        t = x                      # uniform receiver grid
        P[y, :, 0] = np.interp(t, u_mono, x, left=0.0, right=W-1)

    return P

@njit(cache=True, fastmath=True,nogil=True)
def invert_map_1d_monotonic_numba(pixel_shifts_in):
    H, W = pixel_shifts_in.shape
    P = np.empty((H, W, 2), np.float32)
    for y in range(H):
        P[y, :, 1] = y
        s = pixel_shifts_in[y].astype(np.float32)
        x = np.arange(W, dtype=np.float32)
        u = x - s

        # cumulative maximum (monotony)
        u_mono = np.empty_like(u)
        m = -1e30
        for i in range(W):
            ui = u[i]
            if ui < m:
                u_mono[i] = m
            else:
                m = ui
                u_mono[i] = ui

        # linear interpolation t=x by nodes (u_mono -> x)
        xs = np.empty(W, np.float32)
        j = 0
        for k in range(W):
            t = x[k]
            while j+1 < W and u_mono[j+1] <= t:
                j += 1
            j0 = j
            j1 = min(j+1, W-1)
            du = u_mono[j1] - u_mono[j0]
            if du == 0.0:
                xs[k] = x[j1]
            else:
                w = (t - u_mono[j0]) / du
                xs[k] = x[j0] + w * (x[j1] - x[j0])
        P[y, :, 0] = xs
    return P
  
def apply_subpixel_shift(image, pixel_shifts_in, flip_offset):
    """
    Performs a subpixel shift of the image depending on the shift map

    image: original image (H, W, 3), uint8
    pixel_shifts: shift map (H, W), float32
    flip_offset: 0 (parallel) or width (cross-eyed)

    Returns the left stereo frame.
    """
    H, W, _ = image.shape

    # Create a coordinate grid
    x_coords, y_coords = np.meshgrid(np.arange(W), np.arange(H))

    #prepare remap by inverting shift towards destination space:
    P = invert_map_1d_monotonic_numba(pixel_shifts_in.astype(np.float32))
    pixel_shifts = x_coords - P[..., 0]

    
    # Apply shift to x-coordinates
    shifted_x = x_coords - pixel_shifts  # left shift for left eye
    shifted_x = np.clip(shifted_x, 0, W - 1).astype(np.float32)
    y_coords = y_coords.astype(np.float32)

    # Placement in the left half
    sbs_result = np.zeros((H, W * 2, 3), dtype=np.uint8)

    # monotony per line (purly related to depth scale)
    shifted_x = np.maximum.accumulate(shifted_x, axis=1)

    # Interpolation with remap
    shifted_img = cv2.remap(image, shifted_x, y_coords, interpolation=cv2.INTER_LINEAR,borderMode=cv2.BORDER_REFLECT)

    sbs_result[:, flip_offset:flip_offset+W] = shifted_img
             
    return sbs_result


class ImageSBSConverter:

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
                "processing": (["Normal", "test-pixelshifts-x8",  "test-appliedshifts-x8", "test-blackout", "test-shift-grid", "display-values"], {"default": "Normal"}),
            }
        }

    RETURN_TYPES = ("IMAGE", )
    RETURN_NAMES = ("stereoscopic_image", )
    FUNCTION = "process"
    CATEGORY = "image"
    DESCRIPTION = "Create stereoscopic image with automatic shift from depth map. For VR headsets and 3D displays."


    def process(self, base_image, depth_image, depth_scale, depth_offset, switch_sides,
        blur_radius, symetric
        ):

        #print("CONVERTING")
        #define constant
        mode="Parallel"
        invert_depth=True  # The use of depth anything as depth generator requires this.
        
        # DEBUG: start_depth =  time.perf_counter()

        # Get batch size
        B = base_image.shape[0]

        # Process each image in the batch
        sbs_images = []

        for b in range(B):
            # Get the current image from the batch
            current_image = base_image[b]
            current_depth_image = depth_image[b]

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
            height, width = current_image.shape[:2]

            # Convert depth_for_sbs to 8-bit PIL image and resize
            depth_map_resized = cv2.resize((depth_for_sbs * 255).astype(np.uint8),(width, height),interpolation=cv2.INTER_NEAREST)
            depth_np = np.array(depth_map_resized, dtype=np.float32) - 128.0


            # Preparing the source image in NumPy [0–255] and create a "canvas" for the SBS image twice as wide
            current_image_np = (current_image * 255).astype(np.uint8)
            sbs_image = np.zeros((height, width * 2, 3), dtype=np.uint8)

            # Duplicate the source into both halves
            if mode == "Parallel":
                sbs_image[:, width:]  = current_image_np
            else:
                sbs_image[:, :width]  = current_image_np


            # Define the viewing mode (parallel, cross)
            fliped = 0 if mode == "Parallel" else width
            
            depth_scale_local = depth_scale * width * 50.0 / 1000000.0
            depth_offset_local = depth_offset * -8

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
            
            pixel_shifts = (depth_np * depth_scale_local + depth_offset_local).astype(np.float32)# np.int32 to np.float32     
            if blur_radius>0:
                pixel_shifts = cpu_blur(pixel_shifts,blur_radius)
            shifted_half = apply_subpixel_shift(current_image_np, pixel_shifts, fliped)                
            sbs_image[:, fliped:fliped + width] = shifted_half[:, fliped:fliped + width]

            if symetric:
                fliped = width - fliped
                pixel_shifts = (depth_np * -depth_scale_local + depth_offset_local).astype(np.float32)# np.int32 to np.float32     
                if blur_radius>0:
                    pixel_shifts = cpu_blur(pixel_shifts,blur_radius)
                shifted_half = apply_subpixel_shift(current_image_np, pixel_shifts, fliped)                
                sbs_image[:, fliped:fliped + width] = shifted_half[:, fliped:fliped + width]
                fliped = width - fliped

            fillcolor=(0, 0, 0)
            thickness = -1
            
            if crop_size>0:
                cv2.rectangle(sbs_image, (width - crop_size, 0), (width - 1, height - 1), fillcolor, thickness)
            elif crop_size<0:
                cv2.rectangle(sbs_image, (0, 0), (-crop_size - 1, height - 1), fillcolor, thickness)
            if symetric:
                if crop_size2>0:
                    cv2.rectangle(sbs_image, (width, 0), (width+crop_size2, height - 1), fillcolor, thickness)
                elif crop_size2<0:
                    cv2.rectangle(sbs_image, (2*width+crop_size2, 0), (2*width -1, height - 1), fillcolor, thickness)
                        
            if switch_sides:
                sbs_image_swapped = np.zeros((height, width * 2, 3), dtype=np.uint8)
                sbs_image_swapped[:, 0: width] = sbs_image[:, width : width + width]
                sbs_image_swapped[:, width : width + width] = sbs_image[:, 0: width]
                sbs_image = sbs_image_swapped

            
            # Add to our batch lists
            sbs_images.append(sbs_image.astype(np.float32) / 255.0)
            
 
        return sbs_images


