from PIL import Image

from .base_filter import BaseImageFilter


class NoFilter(BaseImageFilter):
    filter_id = "none"
    display_name = "content filter: none"
    icon_name = "filter64_none.png"
    supported_content_types = [BaseImageFilter.CONTENT_TYPE_IMAGE, BaseImageFilter.CONTENT_TYPE_VIDEO]
    preview_content_types = []

    def transform(self, image: Image.Image) -> Image.Image:
        return image
