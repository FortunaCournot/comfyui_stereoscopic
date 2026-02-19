import math

from PIL import Image

from .base_filter import BaseImageFilter


class StereoToVR180Filter(BaseImageFilter):
    filter_id = "stereo_to_vr180"
    display_name = "content filter: stereo to vr180"
    icon_name = "filter64_stereo2vr180.png"
    parameter_defaults = [
        ("fisheye_strength", 1.0),
        ("input_fov", 0.45),
    ]

    def _remap_rectilinear_to_fisheye(self, src_rgb, fov_in_deg: float, strength: float):
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
        max_radius = max(1e-6, math.sqrt(cx * cx + cy * cy))
        fov_in = math.radians(max(60.0, min(160.0, float(fov_in_deg))))
        f_rect = radius / max(1e-6, math.tan(fov_in * 0.5))
        theta_max = math.atan(max_radius / max(1e-6, f_rect))

        ys, xs = np.indices((h, w), dtype=np.float32)
        dx = xs - cx
        dy = ys - cy
        r_fish = np.sqrt(dx * dx + dy * dy)
        theta = (r_fish / max_radius) * theta_max
        theta = np.minimum(theta, theta_max)

        r_rect = f_rect * np.tan(theta)
        phi = np.arctan2(dy, dx)
        map_x = cx + r_rect * np.cos(phi)
        map_y = cy + r_rect * np.sin(phi)

        map_x = np.clip(map_x, 0.0, float(w - 1))
        map_y = np.clip(map_y, 0.0, float(h - 1))

        strength = max(0.0, min(1.0, float(strength)))
        if strength < 0.999:
            map_x = map_x * strength + xs * (1.0 - strength)
            map_y = map_y * strength + ys * (1.0 - strength)

        remapped = cv2.remap(
            src_rgb,
            map_x.astype(np.float32),
            map_y.astype(np.float32),
            interpolation=cv2.INTER_LINEAR,
            borderMode=cv2.BORDER_REPLICATE,
        )
        return remapped

    def _transform_half(self, half_image: Image.Image, fov_in_deg: float, strength: float, has_alpha: bool) -> Image.Image:
        try:
            import numpy as np
        except Exception:
            return half_image

        if has_alpha:
            arr = np.array(half_image.convert("RGBA"), dtype=np.uint8)
            rgb = arr[:, :, :3]
            alpha = arr[:, :, 3]
            warped_rgb = self._remap_rectilinear_to_fisheye(rgb, fov_in_deg, strength)
            warped_alpha = self._remap_rectilinear_to_fisheye(alpha, fov_in_deg, strength)
            out_arr = np.dstack([warped_rgb, warped_alpha]).astype(np.uint8)
            return Image.fromarray(out_arr, mode="RGBA")

        rgb_arr = np.array(half_image.convert("RGB"), dtype=np.uint8)
        warped = self._remap_rectilinear_to_fisheye(rgb_arr, fov_in_deg, strength)
        return Image.fromarray(warped, mode="RGB")

    def transform(self, image: Image.Image) -> Image.Image:
        if image is None:
            return image

        try:
            strength = self.get_parameter("fisheye_strength", 1.0)
            fov_in_norm = self.get_parameter("input_fov", 0.45)
            fov_in_deg = 70.0 + 80.0 * fov_in_norm

            has_alpha = image.mode == "RGBA"
            src = image.convert("RGBA" if has_alpha else "RGB")
            full_w, full_h = src.size

            if full_w < 4 or full_h < 2:
                return src

            left_w = max(1, full_w // 2)
            right_w = max(1, full_w - left_w)

            left = src.crop((0, 0, left_w, full_h))
            right = src.crop((left_w, 0, left_w + right_w, full_h))

            left_out = self._transform_half(left, fov_in_deg, strength, has_alpha)
            right_out = self._transform_half(right, fov_in_deg, strength, has_alpha)

            out = Image.new("RGBA" if has_alpha else "RGB", (full_w, full_h))
            out.paste(left_out, (0, 0))
            out.paste(right_out, (left_w, 0))
            return out
        except Exception:
            return image
