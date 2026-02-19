from typing import List

from .base_filter import BaseImageFilter
from .grayscale_filter import GrayscaleFilter
from .no_filter import NoFilter
from .stereo_to_vr180_filter import StereoToVR180Filter
from .vr180_mono_filter import VR180MonoFilter


def create_content_filter_instances() -> List[BaseImageFilter]:
    return [NoFilter(), GrayscaleFilter(), VR180MonoFilter(), StereoToVR180Filter()]
