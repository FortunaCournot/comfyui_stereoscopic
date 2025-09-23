#Copyright (c) 2025 Fortuna Cournot. MIT License. www.3d-gallery.org

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
      "image": "Teacher_00152_1k.jpg"
    },
    "class_type": "LoadImage",
    "_meta": {
      "title": "Load Image"
    }
  },
  "220": {
    "inputs": {
      "depth_scale": 1.2000000000000002,
      "depth_offset": 0,
      "switch_sides": false,
      "blur_radius": 19,
      "symetric": true,
      "processing": "Normal",
      "base_image": [
        "158",
        0
      ],
      "depth_image": [
        "232",
        0
      ]
    },
    "class_type": "ImageVRConverter",
    "_meta": {
      "title": "Convert to VR"
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
  "232": {
    "inputs": {
      "da_model": [
        "233",
        0
      ],
      "images": [
        "158",
        0
      ]
    },
    "class_type": "DepthAnything_V2",
    "_meta": {
      "title": "Depth Anything V2"
    }
  },
  "233": {
    "inputs": {
      "model": "depth_anything_v2_vitb_fp16.safetensors"
    },
    "class_type": "DownloadAndLoadDepthAnythingV2Model",
    "_meta": {
      "title": "DownloadAndLoadDepthAnythingV2Model"
    }
  }
}
"""

def queue_prompt(prompt):
    response = requests.post("http://"+os.environ["COMFYUIHOST"]+":"+os.environ["COMFYUIPORT"]+"/prompt", json={"prompt": prompt})
    if response.status_code != 200:
        print(response.status_code, response.text)



if len(sys.argv) != 6 + 1:
   print("Invalid arguments were given ("+ str(len(sys.argv)-1) +"). Usage: python " + sys.argv[0] + " depth_model_ckpt_name depth_scale depth_offset blur_radius InputImagePath OutputPathPrefix")
else:
    prompt = json.loads(prompt_text)
    prompt["233"]["inputs"]["model"] = sys.argv[1]
    prompt["220"]["inputs"]["depth_scale"] = float(sys.argv[2])
    prompt["220"]["inputs"]["depth_offset"] = float(sys.argv[3])
    prompt["220"]["inputs"]["blur_radius"] = int(sys.argv[4])
    prompt["220"]["inputs"]["symetric"] = True
    prompt["158"]["inputs"]["image"] = sys.argv[5]
    prompt["227"]["inputs"]["filename_prefix"] = sys.argv[6] 
    
    queue_prompt(prompt)

