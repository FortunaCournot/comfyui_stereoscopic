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
  "171": {
    "inputs": {
      "file": "VR-we-are-RAW1.mp4"
    },
    "class_type": "LoadVideo",
    "_meta": {
      "title": "Load Video"
    }
  },
  "173": {
    "inputs": {
      "video": [
        "171",
        0
      ]
    },
    "class_type": "GetVideoComponents",
    "_meta": {
      "title": "Get Video Components"
    }
  },
  "176": {
    "inputs": {
      "depth_scale": 1.2000000000000002,
      "depth_offset": 0,
      "switch_sides": false,
      "blur_radius": 19,
      "symetric": true,
      "processing": "Normal",
      "base_image": [
        "173",
        0
      ],
      "depth_image": [
        "185",
        0
      ]
    },
    "class_type": "ImageVRConverter",
    "_meta": {
      "title": "Convert to VR"
    }
  },
  "177": {
    "inputs": {
      "filename_prefix": "video/sbstest",
      "format": "auto",
      "codec": "h264",
      "video": [
        "178",
        0
      ]
    },
    "class_type": "SaveVideo",
    "_meta": {
      "title": "Save Video"
    }
  },
  "178": {
    "inputs": {
      "fps": [
        "173",
        2
      ],
      "images": [
        "176",
        0
      ],
      "audio": [
        "173",
        1
      ]
    },
    "class_type": "CreateVideo",
    "_meta": {
      "title": "Create Video"
    }
  },
  "185": {
    "inputs": {
      "da_model": [
        "186",
        0
      ],
      "images": [
        "187",
        0
      ]
    },
    "class_type": "DepthAnything_V2",
    "_meta": {
      "title": "Depth Anything V2"
    }
  },
  "186": {
    "inputs": {
      "model": "depth_anything_v2_vitb_fp16.safetensors"
    },
    "class_type": "DownloadAndLoadDepthAnythingV2Model",
    "_meta": {
      "title": "DownloadAndLoadDepthAnythingV2Model"
    }
  },
  "187": {
    "inputs": {
      "resolution": 1024,
      "algorithm": "INTER_AREA",
      "roundexponent": 4,
      "image": [
        "173",
        0
      ]
    },
    "class_type": "ScaleToResolution",
    "_meta": {
      "title": "ScaleToResolution"
    }
  }
}
"""

def queue_prompt(prompt):
    response = requests.post("http://"+os.environ["COMFYUIHOST"]+":"+os.environ["COMFYUIPORT"]+"/prompt", json={"prompt": prompt})
    if response.status_code != 200:
        print(response.status_code, response.text)


if len(sys.argv) != 7 + 1:
   print("Invalid arguments were given ("+ str(len(sys.argv)-1) +"). Usage: python " + sys.argv[0] + " depth_model_ckpt_name depth_resolution depth_scale depth_offset blur_radius InputVideoPath OutputPathPrefix videoformat videopixfmt videocrf")
else:
    prompt = json.loads(prompt_text)
    prompt["186"]["inputs"]["model"] = sys.argv[1]
    prompt["187"]["inputs"]["resolution"] = sys.argv[2] 
    prompt["176"]["inputs"]["depth_scale"] = float(sys.argv[3])
    prompt["176"]["inputs"]["depth_offset"] = float(sys.argv[4])
    prompt["176"]["inputs"]["blur_radius"] = int(sys.argv[5])
    prompt["176"]["inputs"]["symetric"] = True
    prompt["171"]["inputs"]["file"] = sys.argv[6]
    prompt["177"]["inputs"]["filename_prefix"] = sys.argv[7] 

    
    queue_prompt(prompt)

