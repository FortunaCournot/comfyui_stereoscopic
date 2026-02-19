from PIL import Image

from .base_filter import BaseImageFilter


class NoFilter(BaseImageFilter):
    filter_id = "none"
    display_name = "content filter: none"
    icon_name = "filter64_none.png"

    def transform(self, image: Image.Image) -> Image.Image:
        return image
