import re
from datetime import datetime

class Anything(str):
    def __eq__(self, _) -> bool:
        return True
    def __ne__(self, _) -> bool:
        return False

class RegexSubstitute():
    @classmethod
    def INPUT_TYPES(s):
        return {
            "required": {
                "string": ("STRING", {"multiline": True}),
                "regex_pattern": ("STRING", {"multiline": False}),
                "repl": ("STRING", {"multiline": False}),
                "count": ("INT", {"default": 0, "min": 0}),
                "case_insensitive": ("BOOLEAN", {"default": True}),
                "multiline": ("BOOLEAN", {"default": False}),
                "dotall": ("BOOLEAN", {"default": False}),
            }
        }

    RETURN_TYPES = ("STRING",)
    FUNCTION = "execute"
    CATEGORY = "Stereoscopic"

    def execute(self, string, regex_pattern, repl, count, case_insensitive, multiline, dotall, **kwargs):
        join_delimiter = "\n"

        flags = 0
        if case_insensitive:
            flags |= re.IGNORECASE
        if multiline:
            flags |= re.MULTILINE
        if dotall:
            flags |= re.DOTALL

        try:
            result = re.sub(regex_pattern, repl, string, count, flags)

        except re.error:
            result = ""

        return result,
        

class strftime:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "anything": (Anything("*"), {"forceInput": True}),
                "format": ("STRING", {"default": "%y%m%d%H%M%S", "tooltip": "format string. See https://strftime.org/"}),
            }
        }

    RETURN_TYPES = (Anything("*"), "STRING")
    RETURN_NAMES = ("anything", "string", )
    FUNCTION = "_strftime"

    CATEGORY = "Stereoscopic"

    def _strftime(self, format, anything):
        s = datetime.today().strftime(format)
        return (anything, s)
