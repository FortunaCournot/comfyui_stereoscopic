import torch
import numpy as np
import random
import cv2

# Method from https://github.com/kairess/forensic-watermark/blob/master/forensic-watermark.ipynb

class EncryptWatermark:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "secret": ("INT", {"default": 815}),
                "base_image": ("IMAGE",),
                "watermark": ("IMAGE",),
            }
        }

    RETURN_TYPES = ("IMAGE",)
    RETURN_NAMES = ("encrypted",)
    FUNCTION = "execute"
    CATEGORY = "Stereoscopic"
    DESCRIPTION = "Forensic encrypt image with watermark."

    def execute(self, secret, base_image=None, watermark=None):

        alpha = -1
        
        base_image_s = np.clip(255. * base_image.cpu().numpy().squeeze(), 0, 255).astype(np.uint8)
        watermark_s = np.clip(255. * watermark.cpu().numpy().squeeze(), 0, 255).astype(np.uint8)

        height, width, _ = base_image_s.shape
        watermark_height, watermark_width, _ = watermark_s.shape

        img_f = np.fft.fft2(base_image_s)
        
        y_random_indices, x_random_indices = list(range(height)), list(range(width))
        random.seed(secret)
        random.shuffle(x_random_indices)
        random.shuffle(y_random_indices)
        random_wm = np.zeros((height, width, 3), dtype=np.uint8)

        for y in range(watermark_height):
            for x in range(watermark_width):
                random_wm[y_random_indices[y], x_random_indices[x]] = watermark_s[y, x]


        result_f = img_f + alpha * random_wm

        result = np.fft.ifft2(result_f)
        result = np.real(result)
        #result = result.astype(np.uint8)
        
        return (torch.from_numpy(np.array(result).astype(np.float32) / 255.0).unsqueeze(0), )


class DecryptWatermark:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "secret": ("INT", {"default": 815}),
                "base_image": ("IMAGE",),
                "encrypted": ("IMAGE",)
            }
        }

    RETURN_TYPES = ("IMAGE",)
    RETURN_NAMES = ("watermark",)
    FUNCTION = "execute"
    CATEGORY = "Stereoscopic"
    DESCRIPTION = "Forensic decrypt watermark from image."
    
    def execute(self, secret, base_image=None, encrypted=None):

        alpha = -1

        base_image_s = np.clip(255. * base_image.cpu().numpy().squeeze(), 0, 255).astype(np.uint8)
        encrypted_s = np.clip(255. * encrypted.cpu().numpy().squeeze(), 0, 255).astype(np.uint8)

        height, width, _ = base_image_s.shape
        encrypted_height, encrypted_width, _ = encrypted_s.shape

        img_ori_f = np.fft.fft2(base_image_s)
        img_input_f = np.fft.fft2(encrypted_s)

        watermark = (img_ori_f - img_input_f) / alpha
        watermark = np.real(watermark).astype(np.uint8)

        y_random_indices, x_random_indices = list(range(height)), list(range(width))
        random.seed(secret)
        random.shuffle(x_random_indices)
        random.shuffle(y_random_indices)
        result = np.zeros(watermark.shape, dtype=np.uint8)

        for y in range(height):
            for x in range(width):
                result[y, x] = watermark[y_random_indices[y], x_random_indices[x]]


        return (torch.from_numpy(np.array(result).astype(np.float32) / 255.0).unsqueeze(0), )
