import cv2
import numpy as np
import torch
from PIL import Image
from math import floor, sqrt

class ScaleByFactor:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "image": ("IMAGE",),
                "factor": ("FLOAT", {"default": 1.0, "min": 0.1, "max": 8.0, "step": 0.1, "precision": 1}),
                "algorithm": (["INTER_LINEAR", "INTER_AREA", "INTER_NEAREST", "INTER_CUBIC", "INTER_LANCZOS4"], {"default": "INTER_LINEAR"}),
                "roundexponent": ("INT", {"default": 1, "min": 0, "max": 4, "steps": 1}),
            }
        }

    RETURN_TYPES = ("IMAGE",)
    RETURN_NAMES = ("result",)
    FUNCTION = "execute"
    CATEGORY = "Stereoscopic"
    DESCRIPTION = "Scale image with CV by factor using algorithm. Use INTER_AREA for downscaling. No GPU operation at scale 1. *** Algorithms from OpenCV:  \
INTER_NEAREST - a nearest-neighbor interpolation.  \
INTER_LINEAR - a bilinear interpolation (used by default).  \
INTER_AREA - resampling using pixel area relation. It may be a preferred method for image decimation, as it gives moire’-free results. But when the image is zoomed, it is similar to the INTER_NEAREST method.  \
INTER_CUBIC - a bicubic interpolation over 4x4 pixel neighborhood.  \
INTER_LANCZOS4 - a Lanczos interpolation over 8x8 pixel neighborhood.  "
    
    def execute(self, image, factor=1.0, algorithm="INTER_LINEAR", roundexponent=1):
        """
        INTER_NEAREST - a nearest-neighbor interpolation
        INTER_LINEAR - a bilinear interpolation (used by default)
        INTER_AREA - resampling using pixel area relation. It may be a preferred method for image decimation, as it gives moire’-free results. But when the image is zoomed, it is similar to the INTER_NEAREST method.
        INTER_CUBIC - a bicubic interpolation over 4x4 pixel neighborhood
        INTER_LANCZOS4 - a Lanczos interpolation over 8x8 pixel neighborhood    
        """
        
        round=2**roundexponent
        
        # Get batch size
        B = image.shape[0]

        # Process each image in the batch
        images = []

        for b in range(B):

            algo=cv2.INTER_LINEAR
            if algorithm == "INTER_AREA":
                algo=cv2.INTER_AREA
            elif algorithm == "INTER_NEAREST":
                algo=cv2.INTER_NEAREST
            elif algorithm == "INTER_CUBIC":
                algo=cv2.INTER_CUBIC
            elif algorithm == "INTER_LANCZOS4":
                algo=cv2.INTER_LANCZOS4
            
            if factor != 1.0:

                # Get the current image from the batch
                image_np = image[b].cpu().numpy();
                current_image_np=(image_np * 255).astype(np.uint8)
                image_pil=Image.fromarray(current_image_np)  

                # Get the dimensions of the original img
                width, height = image_pil.size

                newwidth=int( width * factor / round ) * round
                newheight=int( height * factor / round ) * round
                # print(f"[ScaleByFactor] dimension: {width} x {height} -> {newwidth} x {newheight} ")
                
                gpu_mat = cv2.UMat(current_image_np)
                result_mat = cv2.resize(gpu_mat, dsize=(newwidth, newheight), interpolation=algo)
                image_res=cv2.UMat.get(result_mat)
                # Convert to tensor
                image_tensor = torch.tensor(image_res.astype(np.float32) / 255.0)
                # Add to our batch lists
                images.append(image_tensor)
                
            else:
            
                images.append(image[b])
                
        # Stack the results to create batched tensors
        images_batch = torch.stack(images)
 
        return (images_batch, )


class ScaleToResolution:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "image": ("IMAGE",),
                "resolution": ("INT", {"default": 1024, "min": 256, "max": 4096}),
                "algorithm": (["INTER_LINEAR", "INTER_AREA", "INTER_NEAREST", "INTER_CUBIC", "INTER_LANCZOS4"], {"default": "INTER_AREA"}),
                "roundexponent": ("INT", {"default": 4, "min": 0, "max": 4, "step": 1}),
            }
        }

    RETURN_TYPES = ("IMAGE",)
    RETURN_NAMES = ("result",)
    FUNCTION = "execute"
    CATEGORY = "Stereoscopic"
    DESCRIPTION = "If greater, downscale image with CV by factor limited by resolution using algorithm. Use INTER_AREA for downscaling. *** Algorithms from OpenCV:  \
INTER_NEAREST - a nearest-neighbor interpolation.  \
INTER_LINEAR - a bilinear interpolation (used by default).  \
INTER_AREA - resampling using pixel area relation. It may be a preferred method for image decimation, as it gives moire’-free results. But when the image is zoomed, it is similar to the INTER_NEAREST method.  \
INTER_CUBIC - a bicubic interpolation over 4x4 pixel neighborhood.  \
INTER_LANCZOS4 - a Lanczos interpolation over 8x8 pixel neighborhood.  "
    
    def execute(self, image, resolution=1024, algorithm="INTER_LINEAR", roundexponent=1):
        """
        INTER_NEAREST - a nearest-neighbor interpolation
        INTER_LINEAR - a bilinear interpolation (used by default)
        INTER_AREA - resampling using pixel area relation. It may be a preferred method for image decimation, as it gives moire’-free results. But when the image is zoomed, it is similar to the INTER_NEAREST method.
        INTER_CUBIC - a bicubic interpolation over 4x4 pixel neighborhood
        INTER_LANCZOS4 - a Lanczos interpolation over 8x8 pixel neighborhood    
        """
        
        round=2**roundexponent
        
        # Get batch size
        B = image.shape[0]

        # Process each image in the batch
        images = []

        for b in range(B):

            algo=cv2.INTER_LINEAR
            if algorithm == "INTER_AREA":
                algo=cv2.INTER_AREA
            elif algorithm == "INTER_NEAREST":
                algo=cv2.INTER_NEAREST
            elif algorithm == "INTER_CUBIC":
                algo=cv2.INTER_CUBIC
            elif algorithm == "INTER_LANCZOS4":
                algo=cv2.INTER_LANCZOS4
            
        
            # Get the current image from the batch
            image_np = image[b].cpu().numpy();
            current_image_np=(image_np * 255).astype(np.uint8)
            image_pil=Image.fromarray(current_image_np)  

            # Get the dimensions of the original img
            width, height = image_pil.size
            
            current_res = max(width, height)
            factor = float(resolution) / float(current_res)
            
            if factor < 1.0:

                newwidth=int( width * factor / round ) * round
                newheight=int( height * factor / round ) * round
                # print(f"[ScaleToResolution] dimension: {width} x {height} -> {newwidth} x {newheight} ")
                
                gpu_mat = cv2.UMat(current_image_np)
                result_mat = cv2.resize(gpu_mat, dsize=(newwidth, newheight), interpolation=algo)
                image_res=cv2.UMat.get(result_mat)
                # Convert to tensor
                image_tensor = torch.tensor(image_res.astype(np.float32) / 255.0)
                # Add to our batch lists
                images.append(image_tensor)
                    
            else:
            
                images.append(image[b])
                
        # Stack the results to create batched tensors
        images_batch = torch.stack(images)
 
        return (images_batch, )


class CalculateDimensions:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "width": ("INT", {"default": 800, "min": 64, "max": 4096}),
                "height": ("INT", {"default": 450, "min": 64, "max": 2160}),
                "baseresolution": ("INT", {"default": 720, "min": 512, "max": 2160}),
                "factor": ("FLOAT", {"default": 1.0, "min": 0.1, "max": 4.0, "step": 0.1, "precision": 1 }),
                "roundexponent": ("INT", {"default": 4, "min": 0, "max": 6, "step": 1}),
            }
        }

    RETURN_TYPES = ("INT","INT",)
    RETURN_NAMES = ("width","height",)
    FUNCTION = "execute"
    CATEGORY = "Stereoscopic"
    DESCRIPTION = "Calculates dimensions of output image based on aspect of input size, target baseresolution and factor."
    
    def execute(self, width, height, baseresolution, factor, roundexponent):

        round=2**roundexponent
        
        normalized_scaling_multiplier = baseresolution * factor / sqrt( width * height )
        newwidth = floor(width * normalized_scaling_multiplier / round ) * round 
        newheight = floor(normalized_scaling_multiplier * height / round ) * round 
 
        return (floor(newwidth), floor(newheight), )
