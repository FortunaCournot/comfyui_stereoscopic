from PIL import Image


class BaseImageFilter:
    filter_id = "none"
    display_name = "content filter: none"
    icon_name = "filter64_none.png"

    def transform(self, image: Image.Image) -> Image.Image:
        return image
