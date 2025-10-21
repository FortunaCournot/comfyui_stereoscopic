import numpy as np
import torch

class GetResolutionForVR:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "base_image": ("IMAGE",),
            }
        }

    RETURN_TYPES = ("INT", "INT", "INT", "INT",)
    RETURN_NAMES = ("width", "height", "count", "resolution",)
    FUNCTION = "execute"
    CATEGORY = "Stereoscopic"
    DESCRIPTION = "Get resolution for depth image from base image."
    
    def execute(self, base_image):
        return (base_image.shape[2], base_image.shape[1], base_image.shape[0], min(base_image.shape[2], base_image.shape[1]))

class LinearFade:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "images": ("IMAGE",),
                "start": ("FLOAT", {"default": 1.0, "min": 0.0, "max": 1.0}),
                "mid": ("FLOAT", {"default": 0.5, "min": 0.0, "max": 1.0}),
                "end": ("FLOAT", {"default": 0.0, "min": 0.0, "max": 1.0}),
                "midpoint": ("FLOAT", {"default": 0.5, "min": 0.0, "max": 1.0}),
            },
        }

    RETURN_TYPES = ("IMAGE", "FLOAT")
    RETURN_NAMES = ("image", "strength")
    FUNCTION = "fade"
    CATEGORY = "Stereoscopic"


    def fade(self, images, start, mid, end, midpoint):
        num_images = len(images)
        if num_images == 0:
            return ([], [])

        # mid gibt an, wo zwischen 0 und 1 der Übergang liegt
        # → entspricht also einem prozentualen Anteil der Bildliste
        mid_index = int(num_images * mid)
        mid_index = max(1, min(mid_index, num_images - 1))  # Grenzen absichern

        strengths = []
        for i in range(num_images):
            if i < mid_index:
                # Interpolieren zwischen start → midpoint
                t = i / max(1, mid_index - 1)
                strength = start + t * (midpoint - start)
            else:
                # Interpolieren zwischen midpoint → end
                t = (i - mid_index) / max(1, num_images - mid_index - 1)
                strength = midpoint + t * (end - midpoint)
            strengths.append(strength)

        # ⚠️ WICHTIG: separat zurückgeben (nicht als Tupel!)
        return (images, strengths)