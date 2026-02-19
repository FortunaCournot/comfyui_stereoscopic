from typing import List

from .base_filter import BaseImageFilter
from .grayscale_filter import GrayscaleFilter
from .no_filter import NoFilter


def create_content_filter_instances() -> List[BaseImageFilter]:
    return [NoFilter(), GrayscaleFilter()]
