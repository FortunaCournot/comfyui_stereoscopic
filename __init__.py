"""Top-level package for comfyui_stereoscopic."""

import os
import folder_paths


__all__ = [
    "NODE_CLASS_MAPPINGS",
    "NODE_DISPLAY_NAME_MAPPINGS",    
]

__author__ = """Fortuna Cournot"""
__email__ = "fortunacournot@gmail.com"
__version__ = "2.0.1"

print(f'\033[35m[comfyui-stereoscopic] v{__version__}\033[0m Loading...')

from .src.comfyui_stereoscopic.nodes import LOAD_ERRORS

comfy_path = folder_paths.base_path

comfy_input_path = os.path.join(comfy_path, "input")
if not os.path.exists(comfy_input_path):
    os.mkdir(comfy_input_path)
module_input_path = os.path.join(comfy_input_path, "vr")
if not os.path.exists(module_input_path):
    os.mkdir(module_input_path)
if not os.path.exists(module_input_path):
    print(f'\033[35m[comfyui-stereoscopic]\033[0m \033[91mFailed to create ({module_input_path})\033[0m')
    LOAD_ERRORS += 1

comfy_output_path = os.path.join(comfy_path, "output")
if not os.path.exists(comfy_output_path):
    os.mkdir(comfy_output_path)
module_output_path = os.path.join(comfy_output_path, "vr")
if not os.path.exists(module_output_path):
    os.mkdir(module_output_path)
if not os.path.exists(module_output_path):
    print(f'\033[35m[comfyui-stereoscopic]\033[0m \033[91mFailed to create ({module_output_path})\033[0m')
    LOAD_ERRORS += 1

stage_list = ['concat','downscale','dubbing','fullsbs','scaling','singleloop','slides','slideshow','tasks','watermark']

for stage in stage_list:
    stage_input_path = os.path.join(module_input_path, stage)
    if not os.path.exists(stage_input_path):
        os.mkdir(stage_input_path)
    stage_output_path = os.path.join(module_output_path, stage)
    if not os.path.exists(stage_output_path):
        os.mkdir(stage_output_path)
    
substage_path = os.path.join( os.path.join(module_input_path, "dubbing"), "sfx" )
if not os.path.exists(substage_path):
    os.mkdir(substage_path)
substage_path = os.path.join( os.path.join(module_output_path, "dubbing"), "sfx" )
if not os.path.exists(substage_path):
    os.mkdir(substage_path)

substage_path = os.path.join( os.path.join(module_input_path, "downscale"), "4K" )
if not os.path.exists(substage_path):
    os.mkdir(substage_path)
substage_path = os.path.join( os.path.join(module_output_path, "downscale"), "4K" )
if not os.path.exists(substage_path):
    os.mkdir(substage_path)

substage_path = os.path.join( os.path.join(module_input_path, "scaling"), "override" )
if not os.path.exists(substage_path):
    os.mkdir(substage_path)

substage_path = os.path.join( os.path.join(module_input_path, "watermark"), "encrypt" )
if not os.path.exists(substage_path):
    os.mkdir(substage_path)
substage_path = os.path.join( os.path.join(module_output_path, "watermark"), "encrypt" )
if not os.path.exists(substage_path):
    os.mkdir(substage_path)

substage_path = os.path.join( os.path.join(module_input_path, "watermark"), "decrypt" )
if not os.path.exists(substage_path):
    os.mkdir(substage_path)
substage_path = os.path.join( os.path.join(module_output_path, "watermark"), "decrypt" )
if not os.path.exists(substage_path):
    os.mkdir(substage_path)


from .src.comfyui_stereoscopic.nodes import NODE_CLASS_MAPPINGS
from .src.comfyui_stereoscopic.nodes import NODE_DISPLAY_NAME_MAPPINGS

if LOAD_ERRORS == 0:

    comfy_customnode_path = os.path.join(comfy_path, "custom_nodes")
    module_path = os.path.join(comfy_customnode_path, "comfyui_stereoscopic")
    if not os.path.exists(module_path):
        print(f'\033[35m[comfyui-stereoscopic]\033[0m \033[91mFailed to locate module path ({module_path})\033[0m')
    else:
        module_test_path = os.path.join(module_path, "tests")
        if not os.path.exists(module_test_path):
            os.mkdir(module_test_path)
        version_test_path = os.path.join(module_path, ".test_" + __version__ )
        if not os.path.exists(version_test_path):
            print(f'\033[35m[comfyui-stereoscopic]\033[0m \033[93mVersion update detected.\033[0m')
            os.mkdir(version_test_path)
            print(f'\033[35m[comfyui-stereoscopic]\033[0m \033[92mOK.\033[0m')
        else:   # Already tested
            print(f'\033[35m[comfyui-stereoscopic]\033[0m \033[92mOK.\033[0m')

else:

    print(f'\033[35m[comfyui-stereoscopic]\033[0m \033[91mLoad failed ({LOAD_ERRORS}x)\033[0m')



