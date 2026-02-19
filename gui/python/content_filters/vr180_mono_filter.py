import math

from PIL import Image

from .base_filter import BaseImageFilter


class VR180MonoFilter(BaseImageFilter):
    filter_id = "vr180_mono"
    display_name = "content filter: vr180 mono"
    icon_name = "filter64_vr180mono.png"
    parameter_defaults = [
        ("defisheye_strength", 0.714),
        ("output_fov", 0.413),
    ]

    def _remap_fisheye_to_rectilinear(self, src_rgb, fov_out_deg: float, strength: float):
        try:
            import cv2
            import numpy as np
        except Exception:
            return src_rgb

        h, w = src_rgb.shape[:2]
        if h <= 1 or w <= 1:
            return src_rgb

        cx = (w - 1) * 0.5
        cy = (h - 1) * 0.5

        radius = max(1.0, min(cx, cy))
        fov_in = math.radians(180.0)
        fov_out = math.radians(max(60.0, min(160.0, float(fov_out_deg))))

        f_fish = radius / max(1e-6, (fov_in * 0.5))
        f_rect = radius / max(1e-6, math.tan(fov_out * 0.5))

        ys, xs = np.indices((h, w), dtype=np.float32)
        xn = (xs - cx) / f_rect
        yn = (ys - cy) / f_rect

        r = np.sqrt(xn * xn + yn * yn)
        theta = np.arctan(r)
        r_fish = f_fish * theta

        phi = np.arctan2(yn, xn)
        map_x = cx + r_fish * np.cos(phi)
        map_y = cy + r_fish * np.sin(phi)

        strength = max(0.0, min(1.0, float(strength)))
        if strength < 0.999:
            map_x = map_x * strength + xs * (1.0 - strength)
            map_y = map_y * strength + ys * (1.0 - strength)

        remapped = cv2.remap(
            src_rgb,
            map_x.astype(np.float32),
            map_y.astype(np.float32),
            interpolation=cv2.INTER_LINEAR,
            borderMode=cv2.BORDER_CONSTANT,
            borderValue=(0, 0, 0),
        )
        return remapped

    def transform(self, image: Image.Image) -> Image.Image:
        if image is None:
            return image

        try:
            strength = self.get_parameter("defisheye_strength", 1.0)
            fov_out_norm = self.get_parameter("output_fov", 0.45)
            fov_out_deg = 70.0 + 80.0 * fov_out_norm

            has_alpha = image.mode == "RGBA"
            src = image.convert("RGBA" if has_alpha else "RGB")

            full_w, full_h = src.size
            if full_w < 2 or full_h < 2:
                return src

            left_w = max(1, full_w // 2)
            left = src.crop((0, 0, left_w, full_h))

            try:
                import numpy as np
            except Exception:
                return left

            if has_alpha:
                arr = np.array(left, dtype=np.uint8)
                rgb = arr[:, :, :3]
                alpha = arr[:, :, 3]
                corrected_rgb = self._remap_fisheye_to_rectilinear(rgb, fov_out_deg, strength)
                corrected_alpha = self._remap_fisheye_to_rectilinear(alpha, fov_out_deg, strength)
                out_arr = np.dstack([corrected_rgb, corrected_alpha]).astype(np.uint8)
                return Image.fromarray(out_arr, mode="RGBA")

            rgb_arr = np.array(left.convert("RGB"), dtype=np.uint8)
            corrected = self._remap_fisheye_to_rectilinear(rgb_arr, fov_out_deg, strength)
            return Image.fromarray(corrected, mode="RGB")
        except Exception:
            return image
