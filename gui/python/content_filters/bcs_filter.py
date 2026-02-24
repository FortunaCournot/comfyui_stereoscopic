import math
import numpy as np
from PIL import Image, ImageEnhance

from .base_filter import BaseImageFilter


class BrightnessContrastSaturationFilter(BaseImageFilter):
    filter_id = "bcs"
    display_name = "content filter: brightness/contrast/saturation"
    icon_name = "filter64_bcs.png"
    supported_content_types = [BaseImageFilter.CONTENT_TYPE_IMAGE]
    preview_content_types = [BaseImageFilter.CONTENT_TYPE_IMAGE]

    # (name, default, min, max, has_mid)
    parameter_defaults = [
        ("brightness", 0.0, -1.0, 1.0, True),
        ("contrast", 0.0, -1.0, 1.0, True),
        ("saturation", 0.0, -1.0, 1.0, True),
    ]

    def transform(self, image: Image.Image) -> Image.Image:
        if image is None:
            return image

        try:
            b = self.get_parameter("brightness", 0.0)
            c = self.get_parameter("contrast", 1.0)
            s = self.get_parameter("saturation", 1.0)

            has_alpha = image.mode == "RGBA"
            if has_alpha:
                arr = image.convert("RGBA")
                alpha = arr.split()[-1]
                base = arr.convert("RGB")
            else:
                base = image.convert("RGB")

            # Brightness: map [-1,1] -> factor [0,2] by factor = 1 + b
            try:
                bright_factor = 1.0 + float(b)
            except Exception:
                bright_factor = 1.0
            bright_factor = max(0.0, bright_factor)

            # Contrast: interpret c as delta around 1.0 (c in [-1,1] -> factor = 1 + c)
            try:
                contrast_factor = 1.0 + float(c)
            except Exception:
                contrast_factor = 1.0
            contrast_factor = max(0.0, contrast_factor)

            # Saturation (color): interpret s as delta around 1.0 (s in [-1,1] -> factor = 1 + s)
            try:
                color_factor = 1.0 + float(s)
            except Exception:
                color_factor = 1.0
            color_factor = max(0.0, color_factor)

            img = ImageEnhance.Brightness(base).enhance(bright_factor)
            img = ImageEnhance.Contrast(img).enhance(contrast_factor)
            img = ImageEnhance.Color(img).enhance(color_factor)

            if has_alpha:
                img.putalpha(alpha)
                return img
            return img
        except Exception:
            return image

    def suggest_parameters(self, image: Image.Image) -> dict:
        """Estimate reasonable brightness/contrast/saturation parameters for `image`.

        Returns a dict with keys possibly among 'brightness','contrast','saturation'.
        """
        try:
            if image is None:
                return {}
            pil = image.convert('RGB')
            arr = np.array(pil).astype(np.float32) / 255.0
            if arr.size == 0:
                return {}

            # luminance (perceptual)
            lum = 0.2126 * arr[:, :, 0] + 0.7152 * arr[:, :, 1] + 0.0722 * arr[:, :, 2]
            mean_l = float(np.mean(lum))
            std_l = float(np.std(lum))

            # target heuristics
            target_mean = 0.5
            target_std = 0.25

            # brightness parameter b where factor = 1 + b
            bright_factor = target_mean / max(1e-6, mean_l) if mean_l > 0 else 1.0
            bright_param = max(-1.0, min(1.0, bright_factor - 1.0))

            contrast_factor = target_std / max(1e-6, std_l) if std_l > 0 else 1.0
            # contrast_param should be in [-1,1] representing delta from 1.0
            contrast_param = max(-1.0, min(1.0, contrast_factor - 1.0))

            try:
                hsv = np.array(pil.convert('HSV')).astype(np.float32)
                sat = hsv[:, :, 1] / 255.0
                mean_sat = float(np.mean(sat)) if sat.size else 0.5
            except Exception:
                mean_sat = 0.5
            target_sat = 0.8
            sat_factor = target_sat / max(1e-6, mean_sat) if mean_sat > 0 else 1.0
            # saturation param as delta from 1.0 in [-1,1]
            sat_param = max(-1.0, min(1.0, sat_factor - 1.0))

            return {
                'brightness': bright_param,
                'contrast': contrast_param,
                'saturation': sat_param,
            }
        except Exception as e:
            try:
                print(f"[OPTIMAL] suggest_parameters error: {e}", flush=True)
            except Exception:
                pass
            return {}
