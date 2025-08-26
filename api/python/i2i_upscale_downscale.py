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
  "160": {
    "inputs": {
      "value": "out/Apfel"
    },
    "class_type": "PrimitiveString",
    "_meta": {
      "title": "OutputImagePrefix"
    }
  },
  "168": {
    "inputs": {
      "model_name": "RealESRGAN_x4plus.pth"
    },
    "class_type": "UpscaleModelLoader",
    "_meta": {
      "title": "Load Upscale Model"
    }
  },
  "183": {
    "inputs": {
      "image": "VR-we-are-startimage.png"
    },
    "class_type": "LoadImage",
    "_meta": {
      "title": "Load Image"
    }
  },
  "185": {
    "inputs": {
      "filename_prefix": [
        "160",
        0
      ],
      "only_preview": false,
      "images": [
        "194",
        0
      ]
    },
    "class_type": "easy imageSave",
    "_meta": {
      "title": "Save Image (Simple)"
    }
  },
  "186": {
    "inputs": {
      "value": 0.5000000000000001
    },
    "class_type": "easy float",
    "_meta": {
      "title": "Downscale factor"
    }
  },
  "187": {
    "inputs": {
      "base_image": [
        "189",
        0
      ]
    },
    "class_type": "GetResolutionForVR",
    "_meta": {
      "title": "Resolution Info"
    }
  },
  "188": {
    "inputs": {
      "upscale_method": "nearest-exact",
      "width": [
        "193",
        0
      ],
      "height": [
        "193",
        1
      ],
      "crop": "disabled",
      "image": [
        "183",
        0
      ]
    },
    "class_type": "ImageScale",
    "_meta": {
      "title": "Upscale Image"
    }
  },
  "189": {
    "inputs": {
      "upscale_model": [
        "168",
        0
      ],
      "image": [
        "183",
        0
      ]
    },
    "class_type": "ImageUpscaleWithModel",
    "_meta": {
      "title": "Upscale Image (using Model)"
    }
  },
  "190": {
    "inputs": {
      "expression": "a / b",
      "a": [
        "187",
        3
      ],
      "b": [
        "196",
        0
      ]
    },
    "class_type": "MathExpression|pysssss",
    "_meta": {
      "title": "Normalize Sigma"
    }
  },
  "193": {
    "inputs": {
      "base_image": [
        "220",
        0
      ]
    },
    "class_type": "GetResolutionForVR",
    "_meta": {
      "title": "Resolution Info"
    }
  },
  "194": {
    "inputs": {
      "blend_factor": 0.8500000000000002,
      "blend_mode": "normal",
      "image1": [
        "188",
        0
      ],
      "image2": [
        "220",
        0
      ]
    },
    "class_type": "ImageBlend",
    "_meta": {
      "title": "Image Blend"
    }
  },
  "196": {
    "inputs": {
      "value": 1920
    },
    "class_type": "PrimitiveFloat",
    "_meta": {
      "title": "SigmaResolution (Normalizing constant)"
    }
  },
  "216": {
    "inputs": {
      "sigmaX": [
        "190",
        1
      ],
      "sigmaY": [
        "190",
        1
      ],
      "image": [
        "189",
        0
      ]
    },
    "class_type": "Blur (mtb)",
    "_meta": {
      "title": "Blur (mtb)"
    }
  },
  "220": {
    "inputs": {
      "factor": [
        "186",
        0
      ],
      "algorithm": "INTER_AREA",
      "roundexponent": 1,
      "image": [
        "216",
        0
      ]
    },
    "class_type": "ScaleByFactor",
    "_meta": {
      "title": "Scale by Factor"
    }
  }
}
"""

def queue_prompt(prompt):
    response = requests.post("http://"+os.environ["COMFYUIHOST"]+":"+os.environ["COMFYUIPORT"]+"/prompt", json={"prompt": prompt})
    if response.status_code != 200:
        print(response.status_code, response.text)



if len(sys.argv) == 6 + 1:
    prompt = json.loads(prompt_text)
    prompt["183"]["inputs"]["image"] = sys.argv[1]
    prompt["185"]["inputs"]["filename_prefix"] = sys.argv[2] 
    prompt["168"]["inputs"]["model_name"] = sys.argv[3]
    prompt["186"]["inputs"]["value"] = float(sys.argv[4])
    prompt["194"]["inputs"]["blend_factor"] = float(sys.argv[5])
    prompt["196"]["inputs"]["value"] = float(sys.argv[6])
    
    queue_prompt(prompt)
else:
    print("Invalid arguments were given ("+ str(len(sys.argv)-1) +"). Usage: python " + sys.argv[0] + " InputVideoPath OutputPathPrefix upscalemodel scalefactor blendfactor sigmaresolution")

