from PIL import Image


class BaseImageFilter:
    CONTENT_TYPE_IMAGE = "image"
    CONTENT_TYPE_VIDEO = "video"

    filter_id = "none"
    display_name = "content filter: none"
    icon_name = "filter64_none.png"
    parameter_defaults = []
    supported_content_types = [CONTENT_TYPE_IMAGE]
    preview_content_types = [CONTENT_TYPE_IMAGE]

    @staticmethod
    def _clamp(value: float, lo: float, hi: float) -> float:
        try:
            v = float(value)
            if v < lo:
                return lo
            if v > hi:
                return hi
            return v
        except Exception:
            return lo

    def _parse_parameter_defaults(self):
        """Return list of parameter meta tuples: (name, default, min, max).

        Supported entry formats in `parameter_defaults`:
        - (name, default)  -- legacy: default assumed normalized in [0,1], range=[0,1]
        - (name, default, min, max) -- explicit range and default in that range
        """
        result = []
        defaults = getattr(self, "parameter_defaults", []) or []
        for item in defaults:
            try:
                name = str(item[0]).strip()
                if not name:
                    continue
                if len(item) >= 4:
                    lo = float(item[2])
                    hi = float(item[3])
                    default = float(item[1])
                    default = self._clamp(default, lo, hi)
                else:
                    # legacy normalized default in [0,1]
                    lo = 0.0
                    hi = 1.0
                    default = self._clamp(item[1], lo, hi)
                # optional has_mid flag (boolean) at index 4
                has_mid = bool(item[4]) if len(item) >= 5 else False
                result.append((name, default, lo, hi, has_mid))
            except Exception:
                continue
        return result

    def _ensure_parameter_values(self):
        defaults = self._parse_parameter_defaults()
        if not hasattr(self, "_parameter_values") or not isinstance(self._parameter_values, dict):
            self._parameter_values = {name: default for name, default, _lo, _hi, _hm in defaults}
            return self._parameter_values
        # Ensure existing stored values are present and clamped to the
        # declared parameter ranges. Do NOT perform legacy normalized
        # (0..1) -> range conversion here; migration must update persisted
        # storage separately.
        for name, default, lo, hi, _has_mid in defaults:
            if name not in self._parameter_values:
                # missing -> initialize with default
                self._parameter_values[name] = default
            else:
                try:
                    raw = float(self._parameter_values[name])
                    # clamp into declared range
                    self._parameter_values[name] = self._clamp(raw, lo, hi)
                except Exception:
                    self._parameter_values[name] = default
        return self._parameter_values

    def get_parameters(self):
        defaults = self._parse_parameter_defaults()
        values = self._ensure_parameter_values()
        return [(name, self._clamp(values.get(name, default), lo, hi)) for name, default, lo, hi, _has_mid in defaults]

    def get_parameter(self, name: str, fallback: float = 0.0) -> float:
        values = self._ensure_parameter_values()
        defaults = {n: (d, lo, hi, has_mid) for n, d, lo, hi, has_mid in self._parse_parameter_defaults()}
        if name in values:
            if name in defaults:
                _d, lo, hi, _hm = defaults[name]
                return self._clamp(values.get(name), lo, hi)
            return float(values.get(name))
        # fallback: clamp into declared range if available
        if name in defaults:
            _d, lo, hi, _hm = defaults[name]
            return self._clamp(fallback, lo, hi)
        return float(fallback)

    def set_parameter(self, name: str, value: float) -> bool:
        defaults = {param_name: (default, lo, hi, has_mid) for param_name, default, lo, hi, has_mid in self._parse_parameter_defaults()}
        if name not in defaults:
            return False
        values = self._ensure_parameter_values()
        _d, lo, hi, _hm = defaults[name]
        values[name] = self._clamp(value, lo, hi)
        # Parameter applied to instance; no debug logging by default.
        return True

    def _normalize_content_types(self, values, fallback, allow_empty: bool = False):
        source = values if isinstance(values, (list, tuple, set)) else fallback
        if not isinstance(source, (list, tuple, set)):
            source = fallback

        normalized = []
        for item in source:
            try:
                text = str(item).strip().lower()
            except Exception:
                continue
            if text and text not in normalized:
                normalized.append(text)

        if len(normalized) == 0:
            if allow_empty:
                return []
            return [self.CONTENT_TYPE_IMAGE]
        return normalized

    def get_supported_content_types(self):
        return self._normalize_content_types(
            getattr(self, "supported_content_types", [self.CONTENT_TYPE_IMAGE]),
            [self.CONTENT_TYPE_IMAGE],
        )

    def get_preview_supported_content_types(self):
        preview_types = self._normalize_content_types(
            getattr(self, "preview_content_types", [self.CONTENT_TYPE_IMAGE]),
            [self.CONTENT_TYPE_IMAGE],
            allow_empty=True,
        )
        supported = self.get_supported_content_types()
        return [content_type for content_type in preview_types if content_type in supported]

    def transform(self, image: Image.Image) -> Image.Image:
        return image
