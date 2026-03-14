from typing import List

from .base_filter import BaseImageFilter
from .grayscale_filter import GrayscaleFilter
from .no_filter import NoFilter
from .stereo_to_vr180_filter import StereoToVR180Filter
from .vr180_mono_filter import VR180MonoFilter
from .bcs_filter import BrightnessContrastSaturationFilter


def create_content_filter_instances() -> List[BaseImageFilter]:
    # Keep `NoFilter` as the top placeholder, then list real filters.
    return [NoFilter(), BrightnessContrastSaturationFilter(), GrayscaleFilter(), VR180MonoFilter(), StereoToVR180Filter()]
