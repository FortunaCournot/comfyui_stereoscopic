import os
import hashlib
from PIL import Image, ImageOps
import numpy as np
import torch
import folder_paths
E:\SD\vrweare\ComfyUI_windows_portable\ComfyUI\input\vr\check\rate\edit\TK0HGT4PHVGAEYW9R6R562ES20a-251013183746_00001__100.png
class LoadImageWithFilename:
    @classmethod
    def INPUT_TYPES(cls, **kwargs):
        input_dir = folder_paths.get_input_directory()
        files = [f for f in os.listdir(input_dir) if os.path.isfile(os.path.join(input_dir, f))]
        files = folder_paths.filter_files_content_types(files, ["image"])

        # Aktueller Node-Wert, wenn gesetzt
        current_value = kwargs.get("image")
        # Wenn ein externer oder relativer Pfad gesetzt ist → zur Liste hinzufügen
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
    CATEGORY = "image"
    DESCRIPTION = "Load image from dropdown or relative/absolute path."

    @classmethod
    def IS_CHANGED(cls, image):
        path = cls.resolve_path(image)
        if not path or not os.path.isfile(path):
            return None
        try:
            m = hashlib.sha256()
            with open(path, "rb") as f:
                m.update(f.read())
            return m.digest().hex()
        except Exception:
            return None

    @staticmethod
    def resolve_path(image):
        """Löst relative Pfade relativ zum input-Verzeichnis auf."""
        # Falls leer
        if not image:
            return None

        # direkter absoluter Pfad
        if os.path.isabs(image) and os.path.isfile(image):
            return image

        # relativer Pfad → an input anhängen
        input_dir = folder_paths.get_input_directory()
        rel_path = os.path.join(input_dir, image)
        if os.path.isfile(rel_path):
            return rel_path

        # Fallback: prüfen ob Datei im Input ohne zusätzliche Unterordner liegt
        fallback_path = os.path.join(input_dir, os.path.basename(image))
        if os.path.isfile(fallback_path):
            return fallback_path

        return None

    def load_image(self, image):
        image_path = self.resolve_path(image)
        if not image_path or not os.path.isfile(image_path):
            raise FileNotFoundError(f"❌ Datei nicht gefunden: {image}")

        pil_img = Image.open(image_path)
        pil_img = ImageOps.exif_transpose(pil_img)

        mask_tensor = None
        if "A" in pil_img.getbands():
            alpha = pil_img.getchannel("A")
            alpha_np = np.array(alpha).astype(np.float32) / 255.0
            mask_tensor = torch.from_numpy(alpha_np)[None,]

        rgb = pil_img.convert("RGB")
        w, h = rgb.size
        img_np = np.array(rgb).astype(np.float32) / 255.0
        img_tensor = torch.from_numpy(img_np).unsqueeze(0)

        filename = os.path.basename(image_path)
        return (img_tensor, mask_tensor, filename, w, h)

