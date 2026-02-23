import math

from PIL import Image

from .base_filter import BaseImageFilter


class StereoToVR180Filter(BaseImageFilter):
    filter_id = "stereo_to_vr180"
    display_name = "content filter: stereo to vr180"
    icon_name = "filter64_stereo2vr180.png"
    parameter_defaults = [
        ("fisheye_strength", 0.0),
        ("input_fov", 0.75),
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

        # Compute OOB analytically based on the map BEFORE stretch but AFTER
        # strength blending (so strength reduces extreme values first).
        try:
            # use the map values after strength blending (pre-stretch) to compute
            # where the post-stretch coordinates would go out of bounds.
            map_x_pre_stretch = map_x.copy()
            if horizontal_stretch != 0 and horizontal_stretch != 1.0:
                map_x_poststretch = cx + (map_x_pre_stretch - cx) * horizontal_stretch
                mask_post = (map_x_poststretch < 0.0) | (map_x_poststretch > (w - 1))
                # per-column fraction of rows that would go OOB
                col_oob_frac = mask_post.sum(axis=0) / float(h)
                # require most rows in a column to be OOB before marking the column
                col_frac_threshold = 0.9
                cols = np.where(col_oob_frac > col_frac_threshold)[0]
                if cols.size:
                    leftmost = int(cols[0])
                    rightmost = int(cols[-1])
                    self._last_remap_oob_cols = (leftmost, rightmost)
                    self._last_remap_oob_count = int(mask_post.sum())
                else:
                    any_cols = np.where(np.any(mask_post, axis=0))[0]
                    if any_cols.size:
                        self._last_remap_oob_cols = (int(any_cols[0]), int(any_cols[-1]))
                        self._last_remap_oob_count = int(mask_post.sum())
                    else:
                        self._last_remap_oob_cols = (None, None)
                        self._last_remap_oob_count = 0
                # now set map_x to the post-stretch coordinates for further processing
                map_x = map_x_poststretch
        except Exception:
            self._last_remap_oob_cols = (None, None)
            self._last_remap_oob_count = 0
        # debug: emit statistics for map_x before clamping (min/max/mean and OOB flags)
        try:
            try:
                minx = float(np.nanmin(map_x))
                maxx = float(np.nanmax(map_x))
                meanx = float(np.nanmean(map_x))
            except Exception:
                minx = None
                maxx = None
                meanx = None
            oob_left = bool(np.any(map_x < 0.0))
            oob_right = bool(np.any(map_x > (w - 1)))
            print(f"[stereo_to_vr180] map_x pre-clamp min={minx} max={maxx} mean={meanx} oob_left={oob_left} oob_right={oob_right} last_oob_cols={getattr(self,'_last_remap_oob_cols',None)} last_oob_count={getattr(self,'_last_remap_oob_count',None)}")
        except Exception:
            pass

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
        # Debug: optionally force filling left/right edge columns for visibility.
        try:
            # debug flag (default False) — set True manually when needed
            self._debug_force_oob_edges = False
            self._debug_force_oob_width = 50
        except Exception:
            pass

        try:
            # If forcing debug edges, fill left/right N columns. Otherwise use
            # recorded OOB columns from detection.
            arr = remapped
            if arr.ndim == 2:
                arr = arr[:, :, None]
            h_r, w_r = arr.shape[:2]

            if getattr(self, "_debug_force_oob_edges", False):
                N = int(getattr(self, "_debug_force_oob_width", 400))
                N = max(0, min(N, w_r // 2))
                if N > 0:
                    try:
                        # left edge
                        if arr.ndim == 3:
                            arr[:, 0:N, 0] = 255
                            if arr.shape[2] > 1:
                                arr[:, 0:N, 1] = 0
                                arr[:, 0:N, 2] = 0
                            if arr.shape[2] >= 4:
                                arr[:, 0:N, 3] = 255
                        else:
                            arr[:, 0:N] = 255
                        # right edge
                        if arr.ndim == 3:
                            arr[:, w_r - N:w_r, 0] = 255
                            if arr.shape[2] > 1:
                                arr[:, w_r - N:w_r, 1] = 0
                                arr[:, w_r - N:w_r, 2] = 0
                            if arr.shape[2] >= 4:
                                arr[:, w_r - N:w_r, 3] = 255
                        else:
                            arr[:, w_r - N:w_r] = 255
                    except Exception:
                        try:
                            arr[:, 0:N] = 0
                            arr[:, w_r - N:w_r] = 0
                        except Exception:
                            pass
                # assign back
                if remapped.ndim == 2 and arr.shape[2] == 1:
                    remapped = arr[:, :, 0]
                else:
                    remapped = arr
            else:
                if hasattr(self, "_last_remap_oob_cols") and self._last_remap_oob_cols is not None:
                    left, right = self._last_remap_oob_cols
                    if left is not None and right is not None and left <= right:
                        try:
                            l = max(0, int(left))
                            r = min(w_r - 1, int(right))
                            if l <= r:
                                span_width = (r - l + 1)
                                # only fill if span is reasonably narrow (<= 1/4 image width)
                                if span_width <= max(1, w_r // 4):
                                    arr[:, l:r + 1] = 0
                                else:
                                    print(f"[stereo_to_vr180] skipping black-fill for large OOB span {l}-{r} (width={span_width})")
                        except Exception:
                            pass
                        if remapped.ndim == 2 and arr.shape[2] == 1:
                            remapped = arr[:, :, 0]
                        else:
                            remapped = arr
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
            fov_in_norm = self.get_parameter("input_fov", 0.45)
            zoom_out = self.get_parameter("zoom_out", 0.0)
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
