#Copyright (c) 2025 FortunaCournot. MIT License.

import json
import sys
import requests
import os

#This is the ComfyUI api prompt format.

#If you want it for a specific workflow you can "enable dev mode options"
#in the settings of the UI (gear beside the "Queue Size: ") this will enable
#a button on the UI to save workflows in api format.

#keep in mind ComfyUI is pre alpha software so this format will change a bit.

#this is the one for the default workflow
prompt_text = """
{
  "158": {
    "inputs": {
      "image": "SmallIconicTown.png"
    },
    "class_type": "LoadImage",
    "_meta": {
      "title": "Load Image"
    }
  },
  "207": {
    "inputs": {
      "ckpt_name": "depth_anything_v2_vitl.pth",
      "resolution": [
        "222",
        3
      ],
      "image": [
        "229",
        0
      ]
    },
    "class_type": "DepthAnythingV2Preprocessor",
    "_meta": {
      "title": "Depth Anything V2 - Relative"
    }
  },
  "220": {
    "inputs": {
      "depth_scale": 1,
      "depth_offset": 0,
      "switch_sides": false,
      "blur_radius": 45,
      "symetric": true,
      "processing": "Normal",
      "base_image": [
        "229",
        0
      ],
      "depth_image": [
        "207",
        0
      ]
    },
    "class_type": "ImageVRConverter",
    "_meta": {
      "title": "Convert to Side-by-Side"
    }
  },
  "222": {
    "inputs": {
      "base_image": [
        "229",
        0
      ]
    },
    "class_type": "GetResolutionForVR",
    "_meta": {
      "title": "Get Resolution"
    }
  },
  "227": {
    "inputs": {
      "filename_prefix": "SBS",
      "images": [
        "220",
        0
      ]
    },
    "class_type": "SaveImage",
    "_meta": {
      "title": "Save Image"
    }
  },
  "229": {
    "inputs": {
      "anything": [
        "158",
        0
      ]
    },
    "class_type": "easy clearCacheAll",
    "_meta": {
      "title": "Clear Cache All"
    }
  }
}
"""

def queue_prompt(prompt):
    response = requests.post("http://"+os.environ["COMFYUIHOST"]+":"+os.environ["COMFYUIPORT"]+"/prompt", json={"prompt": prompt})
    if response.status_code != 200:
        print(response.status_code, response.text)



if len(sys.argv) != 5 + 1:
   print("Invalid arguments were given ("+ str(len(sys.argv)-1) +"). Usage: python " + sys.argv[0] + " depth_model_ckpt_name depth_scale depth_offset InputImagePath OutputPathPrefix")
else:
    prompt = json.loads(prompt_text)
    prompt["207"]["inputs"]["ckpt_name"] = sys.argv[1]
    prompt["220"]["inputs"]["depth_scale"] = float(sys.argv[2])
    prompt["220"]["inputs"]["depth_offset"] = float(sys.argv[3])
    prompt["220"]["inputs"]["blur_radius"] = int(45)
    prompt["158"]["inputs"]["image"] = sys.argv[4]
    prompt["227"]["inputs"]["filename_prefix"] = sys.argv[5] 
    
    queue_prompt(prompt)

