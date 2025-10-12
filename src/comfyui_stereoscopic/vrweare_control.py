import os
import folder_paths
import time
'''
from PIL import Image, ImageDraw, ImageFont
from comfy.utils import PreviewImage
import numpy as np
comfy_path = folder_paths.base_path
img_files_path = os.path.abspath(os.path.join(comfy_path, 'custom_nodes', 'comfyui_stereoscopic', 'gui', 'img'))
'''

config_files_path = os.path.abspath(os.path.join(folder_paths.get_user_directory(), 'default', 'comfyui_stereoscopic'))


def touch(fname):
    if os.path.exists(fname):
        os.utime(fname, None)
    else:
        open(fname, 'a').close()
        
'''
To be used at start of pipeline, to ensure there is no concurrent process.
'''
class VRwearePause:

    RETURN_TYPES = ("IMAGE",)
    RETURN_NAMES = ("image",)
    FUNCTION = "execute"
    CATEGORY = "Stereoscopic"
    DESCRIPTION = "Pause pipeline, to be used at start of workflow, to ensure there is no concurrent pipeline process. It waits until the pipeline is paused. forwarding is not affected."

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "image": (
                    "IMAGE",
                ),
            }
        }
    
    def execute(self, image):
        touch( os.path.abspath(os.path.join(config_files_path, '.pipelinepause')) )
        pipelineActiveLockPath = os.path.abspath(os.path.join(config_files_path, '.pipelineactive'))
        if os.path.exists(pipelineActiveLockPath):
            print(f"[comfyui_stereoscopic] VR we are pipeline pause requested. Stopping...")

            while os.path.exists(pipelineActiveLockPath):
                time.sleep(1)

        print(f"[comfyui_stereoscopic] paused.")
        return (image,)

'''
To be used at start of pipeline, to ensure there is no concurrent process.
'''
class VRwearePauseLatent:

    RETURN_TYPES = ("LATENT",)
    RETURN_NAMES = ("latent",)
    FUNCTION = "execute"
    CATEGORY = "Stereoscopic"
    DESCRIPTION = "Pause pipeline, to be used at start of workflow, to ensure there is no concurrent pipeline process. It waits until the pipeline is paused. forwarding is not affected."

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "latent": (
                    "LATENT",
                ),
            }
        }
    
    def execute(self, latent):
        touch( os.path.abspath(os.path.join(config_files_path, '.pipelinepause')) )
        pipelineActiveLockPath = os.path.abspath(os.path.join(config_files_path, '.pipelineactive'))
        if os.path.exists(pipelineActiveLockPath):
            print(f"[comfyui_stereoscopic] VR we are pipeline pause requested. Stopping...")
            while os.path.exists(pipelineActiveLockPath):
                time.sleep(1)

        print(f"[comfyui_stereoscopic] paused.")
        return (latent,)

        
class VRweareResume:

    RETURN_TYPES = ("IMAGE",)
    RETURN_NAMES = ("image",)
    FUNCTION = "execute"
    CATEGORY = "Stereoscopic"
    DESCRIPTION = "Resume pipeline. To be used as  the queue."
    
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "image": (
                    "IMAGE",
                ),
            }
       }
    
    def execute(self, image):
        pause_file_path = os.path.abspath(os.path.join(config_files_path, '.pipelinepause'))
        if os.path.exists(pause_file_path): os.remove(pause_file_path)
        return (image,)


