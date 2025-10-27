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
                "mid": ("FLOAT", {"default": 0.0, "min": 0.0, "max": 1.0}),
                "end": ("FLOAT", {"default": 0.0, "min": 0.0, "max": 1.0}),
                "midpoint": ("FLOAT", {"default": 0.2, "min": 0.0, "max": 1.0}),
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
        mid_index = int(num_images * midpoint)
        mid_index = max(1, min(mid_index, num_images - 1))  # Grenzen absichern

        strengths = []
        for i in range(num_images):
            if i < mid_index:
                # Interpolieren zwischen start → midpoint
                t = i / max(1, mid_index - 1)
                strength = start + t * (mid - start)
            else:
                # Interpolieren zwischen midpoint → end
                t = (i - mid_index) / max(1, num_images - mid_index - 1)
                strength = mid + t * (end - mid)
            strengths.append(strength)

        # ⚠️ WICHTIG: separat zurückgeben (nicht als Tupel!)
        return (images, strengths)



class ColorCorrectBatch:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "images": ("IMAGE",),  # Tensor mit Shape [B, H, W, C]
                "saturation": ("FLOAT", {"forceInput": True}),  # Liste von Floats
            },
        }

    RETURN_TYPES = ("IMAGE",)
    RETURN_NAMES = ("corrected_images",)
    FUNCTION = "apply"
    CATEGORY = "Stereoscopic"
    DESCRIPTION = (
        "Wendet eine Sättigungskorrektur auf ein Batch von Bildern an. "
        "Der Input 'images' ist ein Tensor [B, H, W, C]; 'saturation' ist eine Liste von Float-Werten "
        "mit der gleichen Länge wie die Batchgröße."
    )

    def apply(self, images, saturation):
        # Sicherstellen, dass saturation eine Liste ist
        if not isinstance(saturation, (list, tuple)):
            saturation = [saturation]

        batch_size = images.shape[0]
        if len(saturation) != batch_size:
            raise ValueError(
                f"Länge der Sättigungsliste ({len(saturation)}) muss der Batchgröße ({batch_size}) entsprechen."
            )

        # Wir kopieren, um nicht das Original zu verändern
        corrected = []
        weights = torch.tensor([0.299, 0.587, 0.114], device=images.device, dtype=images.dtype)

        for i in range(batch_size):
            img = images[i]  # [H, W, C]
            sat = float(saturation[i])
            gray = torch.sum(img * weights, dim=-1, keepdim=True)  # Luminanzkanal
            adjusted = gray + (img - gray) * sat
            adjusted = torch.clamp(adjusted, 0.0, 1.0)
            corrected.append(adjusted)

        corrected_tensor = torch.stack(corrected, dim=0)  # [B, H, W, C]
        return (corrected_tensor,)
