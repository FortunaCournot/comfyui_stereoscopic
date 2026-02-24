import math
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
        ("contrast", 1.0, 0.0, 2.0, True),
        ("saturation", 1.0, 0.0, 2.0, True),
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

            # Contrast: factor is c
            try:
                contrast_factor = float(c)
            except Exception:
                contrast_factor = 1.0

            # Saturation (color): factor is s
            try:
                color_factor = float(s)
            except Exception:
                color_factor = 1.0

            img = ImageEnhance.Brightness(base).enhance(bright_factor)
            img = ImageEnhance.Contrast(img).enhance(contrast_factor)
            img = ImageEnhance.Color(img).enhance(color_factor)

            if has_alpha:
                img.putalpha(alpha)
                return img
            return img
        except Exception:
            return image
