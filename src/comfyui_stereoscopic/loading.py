import os
import hashlib
from PIL import Image, ImageOps
import numpy as np
import torch
import folder_paths

class LoadImageWithFilename:
    @classmethod
    def INPUT_TYPES(cls, **kwargs):
        input_dir = folder_paths.get_input_directory()
        files = [f for f in os.listdir(input_dir) if os.path.isfile(os.path.join(input_dir, f))]
        files = folder_paths.filter_files_content_types(files, ["image"])
        
        # Aktueller Node-Wert, wenn gesetzt
        current_value = None
        if "image" in kwargs:
            current_value = kwargs["image"]
        elif "default" in kwargs:
            current_value = kwargs["default"]

        # Wenn ein externer Pfad gesetzt ist und nicht in der Liste steht → hinzufügen
        if current_value and current_value not in files:
            files.append(current_value)

        return {
            "required": {
                "image": (sorted(files), {"image_upload": True}),
            }
        }
        
    RETURN_TYPES = ("IMAGE", "MASK", "STRING", "INT", "INT")
    RETURN_NAMES = ("image", "mask", "filename", "width", "height")
    FUNCTION = "load_image"
    CATEGORY = "Stereoscopic"
    DESCRIPTION = "Load image (like builtin) + filename, width & height. If filepath is given, it overrides the image selection, allowing to choose files from other diretories."

    @classmethod
    def IS_CHANGED(cls, image, filepath):
        try:
            if filepath and os.path.isfile(filepath):
                path = filepath
            else:
                path = os.path.join(folder_paths.get_input_directory(), image)
            m = hashlib.sha256()
            with open(path, "rb") as f:
                m.update(f.read())
            return m.digest().hex()
        except Exception:
            return None

    def load_image(self, image, filepath):
        
        if not os.path.isabs(filepath):
            filepath = os.path.join(folder_paths.get_input_directory(), filepath)
    
        if filepath and os.path.isfile(filepath):
            image_path = filepath
        else:
            image_path = os.path.join(folder_paths.get_input_directory(), image)


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


