from inspect import cleandoc
import os
import sys

# Add the current directory to the path so we can import local modules
current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.append(current_dir)

# Import our implementations

LOAD_ERRORS = 0

nodelist="Failed import"

try:
    from converter import ImageVRConverter
    nodelist="ImageVRConverter"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing ImageVRConverter: {e}")

    # Create a placeholder class
    class ImageVRConverter:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading ImageVRConverter"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)

try:
    from tools import GetResolutionForVR
    nodelist=nodelist+", GetResolutionForVR"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing GetResolutionForVR: {e}")

    # Create a placeholder class
    class GetResolutionForVR:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading GetResolutionForVR"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)

try:
    from watermark import EncryptWatermark
    nodelist=nodelist+", EncryptWatermark"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing EncryptWatermark: {e}")

    # Create a placeholder class
    class EncryptWatermark:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading EncryptWatermark"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)

try:
    from watermark import DecryptWatermark
    nodelist=nodelist+", DecryptWatermark"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing DecryptWatermark: {e}")

    # Create a placeholder class
    class DecryptWatermark:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading DecryptWatermark"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)

try:
    from caption import StripXML
    nodelist=nodelist+", StripXML"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing StripXML: {e}")

    # Create a placeholder class
    class StripXML:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading StripXML"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)

try:
    from caption import SaveStrippedUTF8File
    nodelist=nodelist+", SaveStrippedUTF8File"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing SaveStrippedUTF8File: {e}")

    # Create a placeholder class
    class SaveStrippedUTF8File:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading SaveStrippedUTF8File"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)

try:
    from scaling import ScaleByFactor
    nodelist=nodelist+", ScaleByFactor"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing ScaleByFactor: {e}")

    # Create a placeholder class
    class ScaleByFactor:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading ScaleByFactor"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)

try:
    from scaling import ScaleToResolution
    nodelist=nodelist+", ScaleToResolution"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing ScaleToResolution: {e}")

    # Create a placeholder class
    class ScaleToResolution:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading ScaleToResolution"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)


try:
    from scaling import CalculateDimensions
    nodelist=nodelist+", CalculateDimensions"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing CalculateDimensions: {e}")

    # Create a placeholder class
    class CalculateDimensions:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading CalculateDimensions"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)

try:
    from stringutils import RegexSubstitute
    nodelist=nodelist+", RegexSubstitute"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing RegexSubstitute: {e}")

    # Create a placeholder class
    class RegexSubstitute:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading RegexSubstitute"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)


try:
    from stringutils import strftime
    nodelist=nodelist+", strftime"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing strftime: {e}")

    # Create a placeholder class
    class strftime:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading strftime"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)

try:
    from audio import SaveAudioSimple
    nodelist=nodelist+", SaveAudioSimple"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing SaveAudioSimple: {e}")

    # Create a placeholder class
    class SaveAudioSimple:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading SaveAudioSimple"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)


try:
    from vrweare_control import VRwearePause
    nodelist=nodelist+", VRwearePause"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing VRwearePause: {e}")

    # Create a placeholder class
    class VRwearePause:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading VRwearePause"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)

try:
    from vrweare_control import VRwearePauseLatent
    nodelist=nodelist+", VRwearePauseLatent"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing VRwearePauseLatent: {e}")

    # Create a placeholder class
    class VRwearePauseLatent:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading VRwearePauseLatent"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)

try:
    from vrweare_control import VRweareResume
    nodelist=nodelist+", VRweareResume"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing VRweareResume: {e}")

    # Create a placeholder class
    class VRweareResume:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading VRweareResume"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)

try:
    from loading import LoadImageAdvanced
    nodelist=nodelist+", LoadImageAdvanced"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing LoadImageAdvanced: {e}")

    # Create a placeholder class
    class LoadImageAdvanced:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading LoadImageAdvanced"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)

try:
    from tools import LinearFade
    nodelist=nodelist+", LinearFade"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing LinearFade: {e}")

    # Create a placeholder class
    class LinearFade:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading LinearFade"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)

try:
    from tools import ColorCorrectBatch
    nodelist=nodelist+", ColorCorrectBatch"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing ColorCorrectBatch: {e}")

    # Create a placeholder class
    class ColorCorrectBatch:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading ColorCorrectBatch"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)

try:
    from tools import GetVariant
    nodelist=nodelist+", GetVariant"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing GetVariant: {e}")

    # Create a placeholder class
    class GetVariant:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading GetVariant"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)

try:
    from tools import BuildVariantIndex
    nodelist=nodelist+", BuildVariantIndex"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing BuildVariantIndex: {e}")

    # Create a placeholder class
    class BuildVariantIndex:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading BuildVariantIndex"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)


try:
    from tools import VariantPromptBuilder
    nodelist=nodelist+", VariantPromptBuilder"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing VariantPromptBuilder: {e}")

    # Create a placeholder class
    class VariantPromptBuilder:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading VariantPromptBuilder"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)

try:
    from tools import JoinVariantProperties
    nodelist=nodelist+", JoinVariantProperties"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing JoinVariantProperties: {e}")

    # Create a placeholder class
    class JoinVariantProperties:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading JoinVariantProperties"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)

try:
    from tools import BuildThresholdDict
    nodelist=nodelist+", BuildThresholdDict"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing BuildThresholdDict: {e}")

    # Create a placeholder class
    class BuildThresholdDict:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading BuildThresholdDict"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)

try:
    from tools import DefineScalarText
    nodelist=nodelist+", DefineScalarText"
except ImportError as e:
    LOAD_ERRORS += 1
    print(f"[comfyui_stereoscopic] Error importing DefineScalarText: {e}")

    # Create a placeholder class
    class DefineScalarText:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading DefineScalarText"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic"
        def error(self, error):
            return (f"ERROR: {error}",)


print("[comfyui_stereoscopic] Successfully imported " + nodelist)

# A dictionary that contains all nodes you want to export with their names
# NOTE: names should be globally unique
NODE_CLASS_MAPPINGS = {
    "ImageVRConverter" : ImageVRConverter,
    "GetResolutionForVR" : GetResolutionForVR,
    "EncryptWatermark" : EncryptWatermark,
    "DecryptWatermark" : DecryptWatermark,
    "StripXML" : StripXML,
    "SaveStrippedUTF8File" : SaveStrippedUTF8File,
    "ScaleByFactor" : ScaleByFactor,
    "ScaleToResolution" : ScaleToResolution,
    "CalculateDimensions" : CalculateDimensions,    
    "RegexSubstitute" : RegexSubstitute,
    "strftime" : strftime,
    "SaveAudioSimple" : SaveAudioSimple,
    "VRwearePause" : VRwearePause,
    "VRwearePauseLatent" : VRwearePauseLatent,
    "VRweareResume" : VRweareResume,
    "LoadImageAdvanced": LoadImageAdvanced,
    "LinearFade": LinearFade,
    "ColorCorrectBatch": ColorCorrectBatch,
    "GetVariant": GetVariant,
    "BuildVariantIndex": BuildVariantIndex,
    "VariantPromptBuilder": VariantPromptBuilder,
    "JoinVariantProperties": JoinVariantProperties,
    "BuildThresholdDict": BuildThresholdDict,
    "DefineScalarText": DefineScalarText,
}


# A dictionary that contains the friendly/humanly readable titles for the nodes
NODE_DISPLAY_NAME_MAPPINGS = {
    "ImageVRConverter": "Convert to VR",
    "GetResolutionForVR": "Resolution Info",
    "EncryptWatermark": "Encrypt Watermark",
    "DecryptWatermark": "Decrypt Watermark",
    "StripXML" : "Strip XML",
    "SaveStrippedUTF8File" : "Save Stripped UTF-8 File",
    "ScaleByFactor" : "Scale by Factor",
    "ScaleToResolution" : "ScaleToResolution",    
    "CalculateDimensions" : "Calculate Dimensions",    
    "RegexSubstitute": "Regex Substitute",
    "strftime": "strftime",
    "SaveAudioSimple": "Save Audio",
    "VRwearePause": "Pause Pipeline",
    "VRwearePauseLatent": "Pause Pipeline",
    "VRweareResume": "Resume Pipeline",
    "LoadImageAdvanced": "Load Image Advanced",
    "LinearFade": "Linear Fade",
    "ColorCorrectBatch": "ColorCorrectBatch",
    "GetVariant": "Get Variant",
    "BuildVariantIndex": "Build Variant Index",
    "VariantPromptBuilder": "Variant Prompt Builder",
    "JoinVariantProperties": "Join Variant Properties",
    "BuildThresholdDict": "Build Threshold Dict",
    "DefineScalarText": "Define Scalar Text",
}
