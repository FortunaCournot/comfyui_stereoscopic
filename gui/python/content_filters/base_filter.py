from PIL import Image


class BaseImageFilter:
    filter_id = "none"
    display_name = "content filter: none"
    icon_name = "filter64_none.png"
    parameter_defaults = []

    @staticmethod
    def _clamp01(value: float) -> float:
        try:
            return max(0.0, min(1.0, float(value)))
        except Exception:
            return 0.0

    def _normalized_parameter_defaults(self):
        result = []
        defaults = getattr(self, "parameter_defaults", []) or []
        for item in defaults:
            try:
                name = str(item[0]).strip()
                default_value = self._clamp01(item[1])
                if name:
                    result.append((name, default_value))
            except Exception:
                continue
        return result

    def _ensure_parameter_values(self):
        defaults = self._normalized_parameter_defaults()
        if not hasattr(self, "_parameter_values") or not isinstance(self._parameter_values, dict):
            self._parameter_values = {name: default for name, default in defaults}
            return self._parameter_values

        for name, default in defaults:
            if name not in self._parameter_values:
                self._parameter_values[name] = default
            else:
                self._parameter_values[name] = self._clamp01(self._parameter_values[name])
        return self._parameter_values

    def get_parameters(self):
        defaults = self._normalized_parameter_defaults()
        values = self._ensure_parameter_values()
        return [(name, self._clamp01(values.get(name, default))) for name, default in defaults]

    def get_parameter(self, name: str, fallback: float = 0.0) -> float:
        values = self._ensure_parameter_values()
        if name in values:
            return self._clamp01(values.get(name))
        return self._clamp01(fallback)

    def set_parameter(self, name: str, value: float) -> bool:
        valid_names = {param_name for param_name, _ in self._normalized_parameter_defaults()}
        if name not in valid_names:
            return False
        values = self._ensure_parameter_values()
        values[name] = self._clamp01(value)
        return True

    def transform(self, image: Image.Image) -> Image.Image:
        return image
