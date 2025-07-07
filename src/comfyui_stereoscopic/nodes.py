from inspect import cleandoc
import os
import sys

# Add the current directory to the path so we can import local modules
current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.append(current_dir)

# Import our depth estimation implementation
try:
    from converter import ImageSBSConverter
    print("Successfully imported ImageSBSConverter")
except ImportError as e:
    print(f"Error importing ImageSBSConverter: {e}")

    # Create a placeholder class
    class ImageSBSConverter:
        @classmethod
        def INPUT_TYPES(s):
            return {"required": {"error": ("STRING", {"default": "Error loading ImageSBSConverter"})}}
        RETURN_TYPES = ("STRING",)
        FUNCTION = "error"
        CATEGORY = "image"
        def error(self, error):
            return (f"ERROR: {error}",)



# A dictionary that contains all nodes you want to export with their names
# NOTE: names should be globally unique
NODE_CLASS_MAPPINGS = {
    "ImageSBSConverter" : ImageSBSConverter
}

# A dictionary that contains the friendly/humanly readable titles for the nodes
NODE_DISPLAY_NAME_MAPPINGS = {
    "ImageSBSConverter Selector": "Image SBS Converter"
}

