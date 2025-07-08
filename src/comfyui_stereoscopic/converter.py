import torch
from PIL import Image
import numpy as np
import os
import sys
import cv2
import numba
from comfy.utils import ProgressBar
#DEBUG: import time

# https://stackoverflow.com/questions/41703210/inverting-a-real-valued-index-grid/78950229#78950229
def invert_map(F):
    # shape is (h, w, 2), an "xymap"
    (h, w) = F.shape[:2]
    I = np.zeros_like(F)
    I[:,:,1], I[:,:,0] = np.indices((h, w)) # identity map
    P = np.copy(I)
    for i in range(10):
        correction = I - cv2.remap(F, P, None, interpolation=cv2.INTER_LINEAR)
        P += correction * 0.5
    return P

#     
def apply_subpixel_shift(image, pixel_shifts_in, flip_offset, processing, displaytext):
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
    F = np.zeros((H, W, 2), dtype=np.float32)
    F[..., 0] = np.clip(x_coords - pixel_shifts_in, 0, W-1)
    F[..., 1] = y_coords
    P = invert_map(F)
    pixel_shifts = x_coords - P[..., 0]

    
    # Apply shift to x-coordinates
    shifted_x = x_coords - pixel_shifts  # left shift for left eye
    shifted_x = np.clip(shifted_x, 0, W - 1).astype(np.float32)
    y_coords = y_coords.astype(np.float32)

    # Placement in the left half
    sbs_result = np.zeros((H, W * 2, 3), dtype=np.uint8)
    #aimask_img = np.zeros((H, W, 3), dtype=np.uint8)

    if processing == "test-pixelshifts-x8":
        #print(f"test-pixelshifts-x8 exit called...")
        pixel_shifts_x8 = pixel_shifts * 8
        sbs_result[:, flip_offset:flip_offset+W,0] = np.clip(pixel_shifts_x8, 0, 255).astype(np.uint8)
        sbs_result[:, flip_offset:flip_offset+W,1] = np.clip(-pixel_shifts_x8, 0, 255).astype(np.uint8)
        sbs_result[:, flip_offset:flip_offset+W,2] = np.clip(0, 0, 255).astype(np.uint8)
        #print(f"test-appliedshifts-x8 processed: {sbs_result.shape}")
        return sbs_result
        
    # try to improve per line
    for y in range(H):
        for x in range(W):
            xr=W-x-1
            value=shifted_x[y,xr]
            if xr>W-1:
                if value<=previous_value:
                    previous_value=value
                else:
                    shifted_x[y,xr]=previous_value
            else:
                previous_value=value



    if processing == "test-appliedshifts-x8":
        #print(f"test-appliedshifts-x8 exit called...")
        for y in range(H):
            for x in range(W):
                shiftx8=int(shifted_x[y,x]-x) * 8
                sbs_result[y, flip_offset+x, 0] = max(min(-shiftx8, 255), 0)
                sbs_result[y, flip_offset+x, 1] = max(min(shiftx8, 255), 0)
                sbs_result[y, flip_offset+x, 2] = 0
        #print(f"test-appliedshifts-x8 processed: {sbs_result.shape}")
        return sbs_result

    # Interpolation with remap
    shifted_img = cv2.remap(image, shifted_x, y_coords, interpolation=cv2.INTER_LINEAR,borderMode=cv2.BORDER_REFLECT)


    if processing == "test-remap":
        #print(f"test-remap exit called...")
        sbs_result[:, flip_offset:flip_offset+W] = shifted_img
        #print(f"test-remap processed: {sbs_result.shape}")
        return sbs_result

    if processing == "pixel-shift-x8":   
        pixel_shifts_x2 = pixel_shifts * 8
        sbs_result[:, flip_offset:flip_offset+W,0] = np.clip(pixel_shifts_x2, 0, 255).astype(np.uint8)
        sbs_result[:, flip_offset:flip_offset+W,1] = np.clip(pixel_shifts_x2, 0, 255).astype(np.uint8)
        sbs_result[:, flip_offset:flip_offset+W,2] = np.clip(pixel_shifts_x2, 0, 255).astype(np.uint8)
    elif processing == "shift-grid":
        # draw vertical lines
        step=10
        z=0
        for x in np.linspace(start=0, stop=W-1, num=int(W/step)):
            x = int(round(x))
            for y in np.linspace(start=step, stop=H-1, num=int(H/step)):
                cv2.line(image, (int(round(x)), int(round(y-step))), (int(round(x)), int(round(y))), color=(255-int(255*z), int(255*z), 128), thickness=1)
                z=1-z
        # draw horizontal lines
        for y in np.linspace(start=0, stop=H-1, num=int(H/step)):
            y = int(round(y))
            for x in np.linspace(start=step, stop=W-1, num=int(W/step)):
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
                   
    return sbs_result



# Add the current directory to the path so we can import local modules
current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.append(current_dir)

# Import our depth estimation implementation
try:
    from depthestimator import DepthEstimator
    #print("Successfully imported DepthEstimator")
except ImportError as e:
    print(f"Error importing DepthEstimator: {e}")

    # Define a placeholder class that will show a clear error
    class DepthEstimator:
        def __init__(self):
            print("ERROR: DepthEstimator could not be imported!")

        def load_model(self):
            print("ERROR: DepthEstimator model could not be loaded!")
            return None

        def predict_depth(self, image):
            print("ERROR: DepthEstimator model could not be used for inference!")
            # Return a blank depth map
            h, w = image.shape[:2]
            return np.zeros((h, w), dtype=np.float32)

class ImageSBSConverter:
    def __init__(self):
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        self.depth_model = None
        self.original_depths = []

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "base_image": ("IMAGE",),
                "depth_scale": ("FLOAT", {"default": 1.0, "min": 0.0, "max": 10.0, "step": 0.1}),
                "depth_offset": ("FLOAT", {"default": 0.0, "min": -10.0, "max": 10.0, "step": 0.1}),
                "switch_sides": ("BOOLEAN", {"default": False}),
                "blur_radius": ("INT", {"default": 45, "min": -1, "max": 99, "step": 2}),
                "symetric": ("BOOLEAN", {"default": False}),
                "processing": (["Normal", "test-pixelshifts-x8",  "test-appliedshifts-x8", "test-remap", "pixel-shift-x8", "shift-grid", "display-values"], {"default": "Normal"}),
            }
        }

    RETURN_TYPES = ("IMAGE", )
    RETURN_NAMES = ("stereoscopic_image", )
    FUNCTION = "process"
    CATEGORY = "image"
    DESCRIPTION = "Create stereoscopic image with automatic shift from depth map. For VR headsets and 3D displays."

    def load_depth_model(self):
        """
        Load the depth model.
        """
        # Create a new instance of our depth model if needed
        #if self.depth_model is None:
        #print("Creating new DepthEstimator instance")
        self.depth_model = DepthEstimator()

        # Load the model
        try:
            self.depth_model.load_model()
            #print("Successfully loaded DepthEstimator model")
        except Exception as e:
            import traceback
            print(f"Error loading DepthEstimator model: {e}")
            print(traceback.format_exc())

        return self.depth_model

    def generate_depth_map(self, image):
        """
        Generate a depth map from an image or batch of images.
        """
        try:
            # Load the model if not already loaded
            depth_model = self.load_depth_model()

            # Process the image
            B, H, W, C = image.shape
            pbar = ProgressBar(B)
            out = []

            # Store original depth maps for each image in the batch
            self.original_depths = []

            # Process each image in the batch
            for b in range(B):
                # Convert tensor to numpy for processing
                img_np = image[b].cpu().numpy() * 255.0  # Scale to 0-255
                img_np = img_np.astype(np.uint8)

                #print(f"Processing image {b+1}/{B} with shape: {img_np.shape}")

                # Use our depth model's predict_depth method
                depth = depth_model.predict_depth(img_np)

                #print(f"Raw depth output: shape={depth.shape}, min={np.min(depth)}, max={np.max(depth)}, mean={np.mean(depth)}")

                # Make sure depth is normalized to [0,1]
                if np.min(depth) < 0 or np.max(depth) > 1:
                    depth = cv2.normalize(depth, None, 0, 1, cv2.NORM_MINMAX)

                # Save the original depth map for the SBS generation
                self.original_depths.append(depth.copy())

                # Convert back to tensor - keep as grayscale
                # First expand to 3 channels (all with same values) for ComfyUI compatibility
                depth_tensor = torch.from_numpy(depth).float().unsqueeze(0)  # Add channel dimension

                out.append(depth_tensor)
                pbar.update(1)

            # Stack the depth maps
            depth_out = torch.stack(out)

            #print(f"Stacked depth maps: shape={depth_out.shape}, min={depth_out.min().item()}, max={depth_out.max().item()}, mean={depth_out.mean().item()}")

            # Make sure it's in the right format for ComfyUI (B,H,W,C)
            # For grayscale, we need to expand to 3 channels for ComfyUI compatibility
            if len(depth_out.shape) == 3:  # [B,1,H,W]
                depth_out = depth_out.permute(0, 2, 3, 1).cpu().float()  # [B,H,W,1]
                depth_out = depth_out.repeat(1, 1, 1, 3)  # [B,H,W,3]
            elif len(depth_out.shape) == 4:  # [B,C,H,W]
                depth_out = depth_out.permute(0, 2, 3, 1).cpu().float()  # [B,H,W,C]

            #print(f"Final depth map shape: {depth_out.shape}, min: {depth_out.min().item()}, max: {depth_out.max().item()}, mean: {depth_out.mean().item()}")

            return depth_out
        except Exception as e:
            import traceback
            print(f"Error generating depth map: {e}")
            print(traceback.format_exc())
            # Return a blank depth map in case of error
            B, H, W, C = image.shape
            print(f"Creating blank depth map with shape: {(B, H, W, C)}")
            return torch.zeros((B, H, W, C), dtype=torch.float32)

    def process(self, base_image, depth_scale, depth_offset, switch_sides,
        blur_radius, symetric, processing
        ):
        """
        Convert image to a side-by-side (SBS) stereoscopic image.
        The depth map is automatically generated using our custom depth estimation approach.


        Returns:
        - sbs_image: the stereoscopic image(s).
        """

        #define constant
        mode="Parallel"
        invert_depth=False
        
        # DEBUG: start_depth =  time.perf_counter()

        #blur_radius = 0
        
        # Update the depth model parameters
        if self.depth_model is not None:
            # Set default edge_weight for compatibility
            self.depth_model.edge_weight = 0.5
            # Keep gradient_weight for compatibility but set to 0
            self.depth_model.gradient_weight = 0.0
            #self.depth_model.blur_radius = blur_radius

        # Generate depth map
        #print(f"Generating depth map with invert_depth={invert_depth}...")
        depth_map = self.generate_depth_map(base_image)

        # Get batch size
        B = base_image.shape[0]

        # Process each image in the batch
        sbs_images = []
        enhanced_depth_maps = []
        shifted_aimask_tensor_maps = []

        for b in range(B):
            # Get the current image from the batch
            current_image = base_image[b].cpu().numpy()  # Get image b from batch
            current_image_pil = Image.fromarray((current_image * 255).astype(np.uint8))  # Convert to PIL

            # Get the current depth map
            if hasattr(self, 'original_depths') and len(self.original_depths) > b:
                # Use the original grayscale depth map for this image in the batch
                depth_for_sbs = self.original_depths[b].copy()
                #print(f"Using original depth map for image {b+1}/{B}: shape={depth_for_sbs.shape}, min={np.min(depth_for_sbs)}, max={np.max(depth_for_sbs)}")
            else:
                # If original depth is not available, extract from the colored version
                current_depth_map = depth_map[b].cpu().numpy()  # Get depth map b from batch

                # Check [3, H, W]
                if current_depth_map.shape[0] == 3 and len(current_depth_map.shape) == 3:
                    current_depth_map = np.transpose(current_depth_map, (1, 2, 0))

                # Debug info
                #print(f"Depth map shape: {current_depth_map.shape}, min: {current_depth_map.min()}, max: {current_depth_map.max()}, mean: {current_depth_map.mean()}")

                # If we have a colored depth map, use the red channel (which should have our depth values)
                if len(current_depth_map.shape) == 3 and current_depth_map.shape[2] == 3:
                    depth_for_sbs = current_depth_map[:, :, 0].copy()  # Use red channel
                else:
                    depth_for_sbs = current_depth_map.copy()


            # Invert depth if requested (swap foreground/background)
            if invert_depth:
                #print("Inverting depth map (swapping foreground/background)")
                depth_for_sbs = 1.0 - depth_for_sbs

            # Get the dimensions of the original img
            width, height = current_image_pil.size

            # Convert depth_for_sbs to 8-bit PIL image and resize
            depth_map_img = Image.fromarray((depth_for_sbs * 255).astype(np.uint8), mode='L')
            depth_map_img = depth_map_img.resize((width, height), Image.NEAREST)

            # Calculate the shift matrix (pixel_shifts)
            depth_np      = np.array(depth_map_img, dtype=np.float32) - 128.0


            # Preparing the source image in NumPy [0–255] and create a "canvas" for the SBS image twice as wide
            current_image_np = (current_image * 255).astype(np.uint8)
            sbs_image = np.zeros((height, width * 2, 3), dtype=np.uint8)
            shifted_aimask_image = np.zeros((height, width * 2, 3), dtype=np.uint8)

            # Duplicate the source into both halves
            if mode == "Parallel":
                sbs_image[:, width:]  = current_image_np
            else:
                sbs_image[:, :width]  = current_image_np


            # Define the viewing mode (parallel, cross)
            fliped = 0 if mode == "Parallel" else width
            
            displaytext = 'depth_scale ' + str(depth_scale) + ', depth_offset = ' + str(depth_offset)
            
            depth_scale_local = depth_scale * width * 50.0 / 1000000.0
            if symetric:
                depth_scale_local = depth_scale_local / 2.0
            depth_offset_local = depth_offset * -8
            if invert_depth:
                depth_offset_local = -depth_offset_local            
            crop_size = int ((depth_offset + depth_scale) * 4)
            
            pixel_shifts = (depth_np * depth_scale_local + depth_offset_local).astype(np.float32)# np.int32 to np.float32     
            if blur_radius>0:
                gpu_mat = cv2.UMat(pixel_shifts)
                kernel_size = (blur_radius, blur_radius)
                smoothed_gpu = cv2.blur(gpu_mat, kernel_size)
                pixel_shifts = cv2.UMat.get(smoothed_gpu)
            shifted_half = apply_subpixel_shift(current_image_np, pixel_shifts, fliped, processing, displaytext)                
            sbs_image[:, fliped:fliped + width] = shifted_half[:, fliped:fliped + width]
            if processing == "shift-grid":
                shifted_half, shifted_aimask = apply_subpixel_shift(current_image_np, pixel_shifts, fliped, "Normal", displaytext)                
                sbs_image[:, wishifted_aimaskdth - fliped:width - fliped + width] = shifted_half[:, fliped:fliped + width]

            if symetric:
                fliped = width - fliped
                pixel_shifts = (depth_np * -depth_scale_local + depth_offset_local).astype(np.float32)# np.int32 to np.float32     
                if blur_radius>0:
                    gpu_mat = cv2.UMat(pixel_shifts)
                    kernel_size = (blur_radius, blur_radius)
                    smoothed_gpu = cv2.blur(gpu_mat, kernel_size)
                    pixel_shifts = cv2.UMat.get(smoothed_gpu)
                shifted_half = apply_subpixel_shift(current_image_np, pixel_shifts, fliped, processing, displaytext)                
                sbs_image[:, fliped:fliped + width] = shifted_half[:, fliped:fliped + width]
                if processing == "shift-grid":
                    shifted_half, shifted_aimask = apply_subpixel_shift(current_image_np, pixel_shifts, fliped, "Normal", displaytext)                
                    sbs_image[:, wishifted_aimaskdth - fliped:width - fliped + width] = shifted_half[:, fliped:fliped + width]
                fliped = width - fliped

            
            #Blackout parts without sufficient information
            if processing != "shift-grid" and processing != "display-values":
                fillcolor=(255, 0, 0)
                if processing == "Normal" or processing == "display-values": 
                    fillcolor=(0, 0, 0)
                if crop_size>0:
                    cv2.rectangle(sbs_image, (fliped, 0), (crop_size - 1, height - 1), fillcolor, -1)
                elif crop_size<0:
                    cv2.rectangle(sbs_image, (fliped + width - crop_size, 0), (fliped + width - 1, height - 1), fillcolor, -1)

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
      # Print final output stats
        ##print(f"Final SBS image batch shape: {sbs_images_batch.shape}, min: {sbs_images_batch.min().item()}, max: {sbs_images_batch.max().item()}")
 
        return (sbs_images_batch, )
