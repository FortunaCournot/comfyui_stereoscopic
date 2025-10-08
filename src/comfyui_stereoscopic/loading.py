import os
import hashlib
from PIL import Image, ImageOps
import numpy as np
import torch
import folder_paths

class LoadImageWithFilename:
    @classmethod
    def INPUT_TYPES(cls):
        # Wie in der offiziellen Load Image Node
        input_dir = folder_paths.get_input_directory()
        files = [f for f in os.listdir(input_dir) if os.path.isfile(os.path.join(input_dir, f))]
        files = folder_paths.filter_files_content_types(files, ["image"])
        return {
            "required": {
                "image": (sorted(files), {"image_upload": True}),
            }
        }

    RETURN_TYPES = ("IMAGE", "MASK", "STRING", "INT", "INT")
    RETURN_NAMES = ("image", "mask", "filename", "width", "height")
    FUNCTION = "load_image"
    CATEGORY = "Stereoscopic"
    DESCRIPTION = "Load image (like builtin) + filename, width & height"

    @classmethod
    def IS_CHANGED(cls, image):
        if isinstance(image, str):
            try:
                image_path = os.path.join(folder_paths.get_input_directory(), image)
                m = hashlib.sha256()
                with open(image_path, "rb") as f:
                    m.update(f.read())
                return m.digest().hex()
            except Exception:
                return None
        return None

    def load_image(self, image):
        # Falls der Input bereits ein IMAGE ist (z. B. weitergeleitet)
        if not isinstance(image, str):
            if isinstance(image, np.ndarray):
                img_t = torch.from_numpy(image).float()
                if img_t.ndim == 3:
                    img_t = img_t.unsqueeze(0)
                h, w = img_t.shape[1], img_t.shape[2]
                return (img_t, None, "", w, h)
            elif isinstance(image, torch.Tensor):
                h, w = image.shape[1], image.shape[2]
                return (image, None, "", w, h)
            return (image, None, "", 0, 0)

        # Normales Laden vom Dateisystem
        image_path = os.path.join(folder_paths.get_input_directory(), image)
        pil_img = Image.open(image_path)
        pil_img = ImageOps.exif_transpose(pil_img)

        # Maske falls Alpha vorhanden
        mask_tensor = None
        if "A" in pil_img.getbands():
            alpha = pil_img.getchannel("A")
            alpha_np = np.array(alpha).astype(np.float32) / 255.0
            mask_tensor = torch.from_numpy(alpha_np)[None,]

        # RGB Bilddaten
        rgb = pil_img.convert("RGB")
        w, h = rgb.size
        img_np = np.array(rgb).astype(np.float32) / 255.0
        img_tensor = torch.from_numpy(img_np).unsqueeze(0)

        filename = os.path.basename(image_path)
        return (img_tensor, mask_tensor, filename, w, h)


