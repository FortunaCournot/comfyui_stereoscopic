from inspect import cleandoc
import os
import sys

# Add the current directory to the path so we can import local modules
current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.append(current_dir)

# Import our implementations

try:
    from converter import ImageVRConverter
    print("[comfyui_stereoscopic] Successfully imported ImageVRConverter")
except ImportError as e:
    print(f"[comfyui_stereoscopic] Error importing ImageVRConverter: {e}")

    # Create a placeholder class
    class ImageVRConverter:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading ImageVRConverter"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic (VR we are!)"
        def error(self, error):
            return (f"ERROR: {error}",)

try:
    from tools import GetResolutionForVR
    print("[comfyui_stereoscopic] Successfully imported GetResolutionForVR")
except ImportError as e:
    print(f"[comfyui_stereoscopic] Error importing GetResolutionForVR: {e}")

    # Create a placeholder class
    class GetResolutionForVR:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading GetResolutionForVR"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "Stereoscopic (VR we are!)"
        def error(self, error):
            return (f"ERROR: {error}",)



# A dictionary that contains all nodes you want to export with their names
# NOTE: names should be globally unique
NODE_CLASS_MAPPINGS = {
    "ImageVRConverter" : ImageVRConverter,
    "GetResolutionForVR" : GetResolutionForVR
}

# A dictionary that contains the friendly/humanly readable titles for the nodes
NODE_DISPLAY_NAME_MAPPINGS = {
    "ImageVRConverter": "Convert to Side-by-Side",
    "GetResolutionForVR": "Get Resolution"
}

