from PIL import Image, ImageEnhance

from .base_filter import BaseImageFilter


class GrayscaleFilter(BaseImageFilter):
    filter_id = "grayscale"
    display_name = "content filter: grayscale"
    icon_name = "filter64_grayscale.png"

    def transform(self, image: Image.Image) -> Image.Image:
        if image is None:
            return image

        try:
            if image.mode == "RGBA":
                alpha = image.split()[-1]
                desaturated = ImageEnhance.Color(image.convert("RGB")).enhance(0.0).convert("RGBA")
                desaturated.putalpha(alpha)
                return desaturated
            if image.mode != "RGB":
                image = image.convert("RGB")
            return ImageEnhance.Color(image).enhance(0.0)
        except Exception:
            return image
