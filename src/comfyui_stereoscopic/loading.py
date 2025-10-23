import os
import hashlib
from PIL import Image, ImageOps
import numpy as np
import torch
import folder_paths
import comfy.model_management

class LoadImageWithFilename:
    @classmethod
    def INPUT_TYPES(cls, **kwargs):
        input_dir = folder_paths.get_input_directory()
        files = [f for f in os.listdir(input_dir) if os.path.isfile(os.path.join(input_dir, f))]
        files = folder_paths.filter_files_content_types(files, ["image"])

        # Aktueller Node-Wert (z. B. relativer oder absoluter Pfad)
        current_value = kwargs.get("image")
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
    DESCRIPTION = "Load image from dropdown or relative/absolute path."

    @classmethod
    def IS_CHANGED(cls, image):
        """Erzwingt Reload, wenn sich die Datei geändert hat."""
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
        """Löst relative oder absolute Pfade korrekt auf."""
        if not image:
            return None

        # Absoluter Pfad
        if os.path.isabs(image) and os.path.isfile(image):
            return image

        # Relativer Pfad zum input-Verzeichnis
        input_dir = folder_paths.get_input_directory()
        rel_path = os.path.join(input_dir, image)
        if os.path.isfile(rel_path):
            return rel_path

        # Fallback: Prüfen, ob die Datei direkt im Input liegt
        fallback_path = os.path.join(input_dir, os.path.basename(image))
        if os.path.isfile(fallback_path):
            return fallback_path

        return None

    def load_image(self, image):
        """Lädt ein einzelnes Bild und gibt Tensor + Infos zurück."""
        image_path = self.resolve_path(image)
        if not image_path or not os.path.isfile(image_path):
            raise FileNotFoundError(f"❌ Datei nicht gefunden: {image}")

        # Bild öffnen + EXIF-Rotation korrigieren
        pil_img = Image.open(image_path)
        pil_img = ImageOps.exif_transpose(pil_img)

        # Alphakanal extrahieren (Maske)
        mask_tensor = None
        if "A" in pil_img.getbands():
            alpha = pil_img.getchannel("A")
            alpha_np = np.array(alpha).astype(np.float32) / 255.0
            mask_tensor = torch.from_numpy(alpha_np)[None,]

        # RGB konvertieren
        rgb = pil_img.convert("RGB")
        w, h = rgb.size
        img_np = np.array(rgb).astype(np.float32) / 255.0
        img_tensor = torch.from_numpy(img_np).unsqueeze(0)

        # 🔹 Dateiname ergänzen (fix)
        filename = os.path.basename(image_path)

        return (img_tensor, mask_tensor, filename, w, h)


class LoadImageByIndex:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "directory": ("STRING", {"default": ""}),
                "index": ("INT", {"default": 0, "min": 0, "step": 1}),
            }
        }

    RETURN_TYPES = ("IMAGE", "MASK", "STRING", "INT", "INT")
    RETURN_NAMES = ("image", "mask", "filename", "width", "height")
    FUNCTION = "load_image_by_index"
    CATEGORY = "Stereoscopic"

    def _load_single_image(self, path):
        pil_img = Image.open(path)
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

        return img_tensor, mask_tensor, os.path.basename(path), w, h

    def load_image_by_index(self, directory, index):
        if not os.path.isdir(directory):
            raise FileNotFoundError(f"❌ Verzeichnis nicht gefunden: {directory}")

        files = sorted([
            f for f in os.listdir(directory)
            if f.lower().endswith((".png", ".jpg", ".jpeg", ".bmp", ".webp"))
        ])

        if not files:
            raise FileNotFoundError(f"⚠️ Keine unterstützten Bilddateien in: {directory}")

        if index < 0 or index >= len(files):
            raise IndexError(f"Index {index} außerhalb des gültigen Bereichs (0-{len(files)-1})")

        path = os.path.join(directory, files[index])
        return self._load_single_image(path)



class IncrementDirectoryImageLoader:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "directory": ("STRING", {"default": "", "multiline": False}),
            },
            "optional": {
                "reset": ("TRIGGER", ),
                "increment": ("TRIGGER", ),
            }
        }

    RETURN_TYPES = ("STRING", "BOOL", "INT",)
    RETURN_NAMES = ("filename", "finished", "index",)
    FUNCTION = "execute"
    OUTPUT_NODE = False
    CATEGORY = "Stereoscopic/Loop"

    def __init__(self):
        self.files = []
        self.index = 0

    def _scan_files(self, directory):
        valid_ext = (".png", ".jpg", ".jpeg", ".bmp", ".webp")
        self.files = [f for f in sorted(os.listdir(directory)) if f.lower().endswith(valid_ext)]
        self.index = 0

    def execute(self, directory, reset=None, increment=None):
        if reset is not None or not self.files:
            self._scan_files(directory)

        if increment is not None:
            self.index += 1

        finished = self.index >= len(self.files)
        if finished:
            return ("", True, self.index)

        filename = self.files[self.index]
        return (filename, False, self.index)

class LoadSingleImageByFilename:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "directory": ("STRING", {"default": ""}),
                "filename": ("STRING", {"default": ""}),
            }
        }

    RETURN_TYPES = ("IMAGE", "MASK", "INT", "INT")
    RETURN_NAMES = ("image", "mask", "width", "height")
    FUNCTION = "load"
    CATEGORY = "Stereoscopic/Loop"

    def load(self, directory, filename):
        if not filename:
            return (None, None, 0, 0)
        path = os.path.join(directory, filename)
        image = Image.open(path).convert("RGB")
        arr = np.array(image).astype(np.float32) / 255.0
        tensor = torch.from_numpy(arr)[None,]

        h, w = arr.shape[0], arr.shape[1]
        mask = torch.ones((1, h, w), dtype=torch.float32)
        return (tensor, mask, w, h)

class LoopWhileNotFinished:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "start": ("TRIGGER",),
                "finished": ("BOOL",),
            }
        }

    RETURN_TYPES = ("TRIGGER",)
    RETURN_NAMES = ("increment",)
    FUNCTION = "execute"
    OUTPUT_NODE = False
    CATEGORY = "Stereoscopic/Loop"

    def execute(self, start, finished):
        if not finished:
            return (True,)  # Trigger nächsten Increment
        return (None,)  # Schleife stoppen



class StartLoopTrigger:
    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {}}

    # EXEC Node → kein RETURN_NAME
    RETURN_TYPES = ()            # 👈 wichtig, auch wenn leer
    OUTPUT_NODE = True
    FUNCTION = "trigger"

    CATEGORY = "Stereoscopic/Utility"
    DESCRIPTION = "Gibt bei Workflowstart ein EXEC-Signal aus."

    def trigger(self):
        # Kein return notwendig — einfach nur EXEC triggern
        pass

