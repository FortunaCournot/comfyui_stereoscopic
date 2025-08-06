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
  "13": {
    "inputs": {
      "secret": [
        "32",
        0
      ],
      "base_image": [
        "17",
        0
      ],
      "watermark": [
        "22",
        0
      ]
    },
    "class_type": "EncryptWatermark",
    "_meta": {
      "title": "Encrypt Watermark"
    }
  },
  "17": {
    "inputs": {
      "image": "VR-we-are-closing-credits.png"
    },
    "class_type": "LoadImage",
    "_meta": {
      "title": "Load Image"
    }
  },
  "18": {
    "inputs": {
      "image": "sample_memories.PNG"
    },
    "class_type": "LoadImage",
    "_meta": {
      "title": "Load Watermark"
    }
  },
  "22": {
    "inputs": {
      "upscale_method": "nearest-exact",
      "width": [
        "24",
        0
      ],
      "height": [
        "24",
        1
      ],
      "crop": "disabled",
      "image": [
        "18",
        0
      ]
    },
    "class_type": "ImageScale",
    "_meta": {
      "title": "Upscale Image"
    }
  },
  "24": {
    "inputs": {
      "base_image": [
        "17",
        0
      ]
    },
    "class_type": "GetResolutionForVR",
    "_meta": {
      "title": "Resolution Info"
    }
  },
  "32": {
    "inputs": {
      "value": 354346
    },
    "class_type": "PrimitiveInt",
    "_meta": {
      "title": "Secret Seed"
    }
  },
  "34": {
    "inputs": {
      "filename_prefix": "ComfyUI",
      "images": [
        "13",
        0
      ]
    },
    "class_type": "SaveImage",
    "_meta": {
      "title": "Save Image"
    }
  }
}
"""

def queue_prompt(prompt):
    response = requests.post("http://"+os.environ["COMFYUIHOST"]+":"+os.environ["COMFYUIPORT"]+"/prompt", json={"prompt": prompt})
    if response.status_code != 200:
        print(response.status_code, response.text)


if len(sys.argv) != 4 + 1:
   print("Invalid arguments were given ("+ str(len(sys.argv)-1) +"). Usage: python " + sys.argv[0] + " InputImagePath WatermarkImagePath OutputPathPrefix secret")
else:
    prompt = json.loads(prompt_text)
    prompt["17"]["inputs"]["image"] = sys.argv[1]
    prompt["18"]["inputs"]["image"] = sys.argv[2]
    prompt["34"]["inputs"]["filename_prefix"] = sys.argv[3] 
    prompt["32"]["inputs"]["value"] = int(sys.argv[4])
    
    queue_prompt(prompt)

