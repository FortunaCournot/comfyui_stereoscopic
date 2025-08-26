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
  "1": {
    "inputs": {
      "ckpt_name": "film_net_fp32.pt",
      "clear_cache_after_n_frames": 8,
      "multiplier": [
        "8",
        0
      ],
      "frames": [
        "6",
        0
      ]
    },
    "class_type": "FILM VFI",
    "_meta": {
      "title": "FILM VFI"
    }
  },
  "4": {
    "inputs": {
      "expression": "b * a",
      "a": [
        "6",
        2
      ],
      "b": [
        "8",
        0
      ]
    },
    "class_type": "MathExpression|pysssss",
    "_meta": {
      "title": "double fps"
    }
  },
  "5": {
    "inputs": {
      "file": "VR-we-are-RAW1.mp4"
    },
    "class_type": "LoadVideo",
    "_meta": {
      "title": "Load Video"
    }
  },
  "6": {
    "inputs": {
      "video": [
        "5",
        0
      ]
    },
    "class_type": "GetVideoComponents",
    "_meta": {
      "title": "Get Video Components"
    }
  },
  "8": {
    "inputs": {
      "value": 2
    },
    "class_type": "PrimitiveInt",
    "_meta": {
      "title": "Int"
    }
  },
  "10": {
    "inputs": {
      "fps": [
        "4",
        1
      ],
      "images": [
        "1",
        0
      ],
      "audio": [
        "6",
        1
      ]
    },
    "class_type": "CreateVideo",
    "_meta": {
      "title": "Create Video"
    }
  },
  "11": {
    "inputs": {
      "filename_prefix": "vr/interpolate/intermediate/result",
      "format": "mp4",
      "codec": "h264",
      "video": [
        "10",
        0
      ]
    },
    "class_type": "SaveVideo",
    "_meta": {
      "title": "Save Video"
    }
  }
}
"""

def queue_prompt(prompt):
    response = requests.post("http://"+os.environ["COMFYUIHOST"]+":"+os.environ["COMFYUIPORT"]+"/prompt", json={"prompt": prompt})
    if response.status_code != 200:
        print(response.status_code, response.text)


if len(sys.argv) != 3 + 1:
   print("Invalid arguments were given ("+ str(len(sys.argv)-1) +"). Usage: python " + sys.argv[0] + " InputVideoPath OutputPathPrefix multiplicator")
else:
    prompt = json.loads(prompt_text)
    prompt["5"]["inputs"]["file"] = sys.argv[1]
    prompt["11"]["inputs"]["filename_prefix"] = sys.argv[2] 
    prompt["8"]["inputs"]["value"] = int(sys.argv[3])
    
    queue_prompt(prompt)

