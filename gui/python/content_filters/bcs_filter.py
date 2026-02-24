import math
import numpy as np
from PIL import Image, ImageEnhance
try:
    import cv2
except Exception:
    cv2 = None

from .base_filter import BaseImageFilter


def lab_chroma(pil_image: Image.Image, factor: float) -> Image.Image:
    """Experimental: scale chroma in CIELab color space.

    - `pil_image`: PIL.Image (RGB or RGBA accepted)
    - `factor`: multiplicative factor for chroma (1.0 = no change)

    Returns a new PIL.Image. If OpenCV (`cv2`) is not available, raises RuntimeError.
    This function is experimental and intended as an opt-in alternative to simple
    HSV-based saturation scaling because it preserves hue while modifying chroma.
    """
    if pil_image is None:
        return pil_image
    if cv2 is None:
        raise RuntimeError("OpenCV (cv2) is required for Lab chroma scaling")

    # Preserve alpha if present
    has_alpha = pil_image.mode == 'RGBA'
    if has_alpha:
        alpha = pil_image.split()[-1]
        rgb = pil_image.convert('RGB')
    else:
        rgb = pil_image.convert('RGB')

    arr = np.array(rgb)
    # OpenCV uses BGR ordering
    bgr = cv2.cvtColor(arr, cv2.COLOR_RGB2BGR)
    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    L = lab[:, :, 0]
    A = lab[:, :, 1].astype(np.float32) - 128.0
    Bc = lab[:, :, 2].astype(np.float32) - 128.0

    # Scale chroma components (A,B) around neutral (128)
    A = 128.0 + A * float(factor)
    Bc = 128.0 + Bc * float(factor)
    A = np.clip(A, 0.0, 255.0)
    Bc = np.clip(Bc, 0.0, 255.0)

    lab2 = np.stack([L, A, Bc], axis=2).astype(np.uint8)
    bgr2 = cv2.cvtColor(lab2, cv2.COLOR_LAB2BGR)
    rgb2 = cv2.cvtColor(bgr2, cv2.COLOR_BGR2RGB)
    out = Image.fromarray(rgb2)
    if has_alpha:
        out.putalpha(alpha)
    return out


def lab_chroma_suggest(pil_image: Image.Image) -> dict:
    """Experimental suggestion: estimate a saturation delta based on Lab chroma.

    Returns a dict {'saturation': delta} where delta is in [-0.5, 0.5].
    """
    try:
        if pil_image is None:
            return {}
        if cv2 is None:
            # fallback to HSV-based median if OpenCV not available
            pil = pil_image.convert('RGB')
            hsv = np.array(pil.convert('HSV')).astype(np.float32)
            sat = hsv[:, :, 1] / 255.0
            if sat.size:
                mean_sat = float(np.median(sat))
            else:
                mean_sat = 0.5
            # Only suggest change if mean saturation is notably outside the central band
            low_thr = 0.3
            high_thr = 0.7
            if low_thr <= mean_sat <= high_thr:
                return {}
            # Compute small proportional correction toward target (gain small)
            target_sat = 0.5
            gain = 0.25
            delta = (target_sat - mean_sat) * gain
            delta = max(-0.25, min(0.25, delta))
            return {'saturation': float(delta)}

        # Use Lab chroma estimation
        pil = pil_image.convert('RGB')
        arr = np.array(pil)
        bgr = cv2.cvtColor(arr, cv2.COLOR_RGB2BGR)
        lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
        A = lab[:, :, 1].astype(np.float32) - 128.0
        Bc = lab[:, :, 2].astype(np.float32) - 128.0
        chroma = np.sqrt(A * A + Bc * Bc)
        if chroma.size == 0:
            return {}
        # robust estimator: median normalized to [0,1] by 127.0
        median_chroma = float(np.median(chroma)) / 127.0
        median_chroma = max(0.0, min(1.0, median_chroma))
        # Only suggest when chroma is notably outside the central band; otherwise leave unchanged
        low_thr = 0.3
        high_thr = 0.7
        if low_thr <= median_chroma <= high_thr:
            return {}
        target_chroma = 0.5
        gain = 0.25
        delta = (target_chroma - median_chroma) * gain
        delta = max(-0.25, min(0.25, delta))
        return {'saturation': float(delta)}
    except Exception:
        return {}


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
            c = self.get_parameter("contrast", 0.0)
            s = self.get_parameter("saturation", 0.0)

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

            # Apply saturation/chroma scaling using Lab if available (preserves hue better)
            try:
                # Always prefer Lab chroma scaling when OpenCV is available.
                if cv2 is not None and abs(color_factor - 1.0) > 1e-6:
                    try:
                        img = lab_chroma(img, color_factor)
                    except Exception:
                        img = ImageEnhance.Color(img).enhance(color_factor)
                else:
                    img = ImageEnhance.Color(img).enhance(color_factor)
            except Exception:
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
                # use a robust estimator (median) and ignore near-zero noise
                if sat.size:
                    mean_sat = float(np.median(sat))
                else:
                    mean_sat = 0.5
            except Exception:
                mean_sat = 0.5
            target_sat = 0.8
            # avoid division by tiny numbers and extreme scaling
            # make estimator more conservative: larger min_mean, smaller alpha, tighter clamp
            min_mean = 0.05
            scaled = target_sat / max(min_mean, mean_sat)
            # damp the adjustment to avoid full-step jumps (alpha in (0,1])
            alpha = 0.35
            damped_factor = 1.0 + (scaled - 1.0) * alpha
            # final parameter is delta from 1.0, clamp to a conservative range (±0.5)
            sat_param = max(-0.5, min(0.5, damped_factor - 1.0))

            # Conservative choice: do not auto-adjust saturation by default because
            # automatic saturation changes often produce unnatural primary colors
            # and there is no single "TV-style" universal algorithm. Return only
            # brightness and contrast suggestions; keep saturation unchanged.
            return {
                'brightness': bright_param,
                'contrast': contrast_param,
            }
        except Exception as e:
            try:
                print(f"[OPTIMAL] suggest_parameters error: {e}", flush=True)
            except Exception:
                pass
            return {}
