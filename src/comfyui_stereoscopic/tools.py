import torch



class GetResolutionForDepth:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "base_image": ("IMAGE",),
            }
        }

    RETURN_TYPES = ("INT", "INT", "INT", "INT",)
    RETURN_NAMES = ("width", "height", "count", "resolution",)
    FUNCTION = "execute"
    CATEGORY = "image"
    DESCRIPTION = "Get resolution for depth image from base image."
    
    def execute(self, base_image):
        return (base_image.shape[2], base_image.shape[1], base_image.shape[0], min(base_image.shape[2], base_image.shape[1]))
  