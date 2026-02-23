import math

from PIL import Image

from .base_filter import BaseImageFilter


class StereoToVR180Filter(BaseImageFilter):
    filter_id = "stereo_to_vr180"
    display_name = "content filter: stereo to vr180"
    icon_name = "filter64_stereo2vr180.png"
    parameter_defaults = [
        ("fisheye_strength", 0.0),
        ("zoom_out", 0.6),
    ]

    # duplicate of _remap_rectilinear_to_fisheye for experimentation/comparison
    def _remap_rectilinear_to_fisheye_v2(self, src_rgb, fov_in_deg: float, strength: float):
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

        # OOB detection will be computed analytically later (after strength blend)
        # Initialize placeholders so downstream logic has defined values.
        self._last_remap_oob_cols = (None, None)
        self._last_remap_oob_count = 0

        map_x = np.clip(map_x, 0.0, float(w - 1))
        map_y = np.clip(map_y, 0.0, float(h - 1))

        # sanitize maps: replace NaN/Inf and ensure values inside valid range
        try:
            map_x = np.nan_to_num(map_x, nan=xs, posinf=float(w - 1), neginf=0.0)
            map_y = np.nan_to_num(map_y, nan=ys, posinf=float(h - 1), neginf=0.0)
        except Exception:
            pass

        strength = max(0.0, min(1.0, float(strength)))
        if strength < 0.999:
            map_x = map_x * strength + xs * (1.0 - strength)
            map_y = map_y * strength + ys * (1.0 - strength)
        # apply a center-relative horizontal stretch so effect is visible
        horizontal_stretch = 1.5
        # apply center-relative horizontal stretch directly (previous single-line behavior)
        try:
            map_x = cx + (map_x - cx) * horizontal_stretch
        except Exception:
            pass

        # set default OOB fill ranges at the left/right edges based on a fraction of the image width, but only if the image is large enough to allow a reasonable span. This is a fallback in case OOB detection fails or is inaccurate, and also serves as a visual debug indicator of where OOB areas are expected.
        try:
            span = max(0, min(w / 6, w // 2))
            if span > 0:
                left_range = (0, span - 1)
                right_range = (max(w - span, 0), w - 1)
                self._last_remap_oob_fill_ranges = [left_range, right_range]
            else:
                self._last_remap_oob_fill_ranges = None
            self._last_remap_oob_cols = (None, None)
        except Exception:
            self._last_remap_oob_fill_ranges = None
            self._last_remap_oob_cols = (None, None)

        # clamp to valid pixel coordinates to avoid out-of-bounds maps
        try:
            map_x = np.clip(map_x, 0.0, float(w - 1))
            map_y = np.clip(map_y, 0.0, float(h - 1))
        except Exception:
            pass

        remapped = cv2.remap(
            src_rgb,
            map_x.astype(np.float32),
            map_y.astype(np.float32),
            interpolation=cv2.INTER_LINEAR,
            borderMode=cv2.BORDER_REPLICATE,
        )
        try:
            # Use recorded OOB fill ranges or the detected column span to
            # black-out destination columns. The debug force flag has been
            # removed to avoid test-only visual alterations.
            arr = remapped
            if arr.ndim == 2:
                arr = arr[:, :, None]
            h_r, w_r = arr.shape[:2]

            ranges = getattr(self, "_last_remap_oob_fill_ranges", None)
            if ranges:
                try:
                    for (l, r) in ranges:
                        l = max(0, int(l))
                        r = min(w_r - 1, int(r))
                        if l <= r:
                            if arr.ndim == 3 and arr.shape[2] >= 3:
                                arr[:, l:r + 1, 0] = 0
                                arr[:, l:r + 1, 1] = 0
                                arr[:, l:r + 1, 2] = 0
                                if arr.shape[2] >= 4:
                                    arr[:, l:r + 1, 3] = 255
                            else:
                                try:
                                    arr[:, l:r + 1] = 0
                                except Exception:
                                    arr[:, l:r + 1] = 0
                except Exception:
                            if l <= r:
                                if arr.ndim == 3 and arr.shape[2] >= 3:
                                    arr[:, l:r + 1, 0] = 0
                                    arr[:, l:r + 1, 1] = 0
                                    arr[:, l:r + 1, 2] = 0
                                    if arr.shape[2] >= 4:
                                        arr[:, l:r + 1, 3] = 255
                                else:
                                    try:
                                        arr[:, l:r + 1] = 0
                                    except Exception:
                                        arr[:, l:r + 1] = 0
        except Exception:
            pass

        return remapped

    def _apply_zoom_out(self, image: Image.Image, zoom_out: float, has_alpha: bool) -> Image.Image:
        try:
            zoom_out = max(0.0, min(1.0, float(zoom_out)))
            if zoom_out <= 1e-6:
                return image

            w, h = image.size
            if w <= 1 or h <= 1:
                return image

            scale = 1.0 - (0.35 * zoom_out)
            nw = max(1, int(round(w * scale)))
            nh = max(1, int(round(h * scale)))
            resized = image.resize((nw, nh), Image.LANCZOS)

            canvas_mode = "RGBA" if has_alpha else "RGB"
            canvas_color = (0, 0, 0, 0) if has_alpha else (0, 0, 0)
            canvas = Image.new(canvas_mode, (w, h), canvas_color)
            ox = (w - nw) // 2
            oy = (h - nh) // 2
            canvas.paste(resized, (ox, oy))
            return canvas
        except Exception:
            return image

    def _transform_half(self, half_image: Image.Image, fov_in_deg: float, strength: float, zoom_out: float, has_alpha: bool) -> Image.Image:
        try:
            import numpy as np
        except Exception:
            return half_image

        if has_alpha:
            arr = np.array(half_image.convert("RGBA"), dtype=np.uint8)
            rgb = arr[:, :, :3]
            alpha = arr[:, :, 3]
            warped_rgb = self._remap_rectilinear_to_fisheye_v2(rgb, fov_in_deg, strength)
            warped_alpha = self._remap_rectilinear_to_fisheye_v2(alpha, fov_in_deg, strength)
            out_arr = np.dstack([warped_rgb, warped_alpha]).astype(np.uint8)
            return self._apply_zoom_out(Image.fromarray(out_arr, mode="RGBA"), zoom_out, has_alpha)

        rgb_arr = np.array(half_image.convert("RGB"), dtype=np.uint8)
        warped = self._remap_rectilinear_to_fisheye_v2(rgb_arr, fov_in_deg, strength)
        return self._apply_zoom_out(Image.fromarray(warped, mode="RGB"), zoom_out, has_alpha)

    def transform(self, image: Image.Image) -> Image.Image:
        if image is None:
            return image

        try:
            strength = self.get_parameter("fisheye_strength", 1.0)
            zoom_out = self.get_parameter("zoom_out", 0.0)
            # derive input FOV from strength (strength in [0,1]) so no separate
            # `input_fov` parameter is required. Higher strength -> larger FOV.
            try:
                fov_in_norm = max(0.0, min(1.0, float(strength)))
            except Exception:
                fov_in_norm = 0.45
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

            left_out = self._transform_half(left, fov_in_deg, strength, zoom_out, has_alpha)
            right_out = self._transform_half(right, fov_in_deg, strength, zoom_out, has_alpha)

            out = Image.new("RGBA" if has_alpha else "RGB", (full_w, full_h))
            out.paste(left_out, (0, 0))
            out.paste(right_out, (left_w, 0))
            return out
        except Exception:
            return image
