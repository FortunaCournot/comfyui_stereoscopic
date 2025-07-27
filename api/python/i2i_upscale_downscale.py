#Copyright (c) 2025 FortunaCournot. MIT License.

import json
import sys
from urllib import request
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
      "image": "Apfeltest.JPG"
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
      "title": "Downscale"
    }
  },
  "187": {
    "inputs": {
      "base_image": [
        "189",
        0
      ]
    },
    "class_type": "GetResolutionForDepth",
    "_meta": {
      "title": "Get Resolution"
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
  "191": {
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
  "192": {
    "inputs": {
      "scale_by": [
        "186",
        0
      ],
      "images": [
        "191",
        0
      ]
    },
    "class_type": "easy imageScaleDownBy",
    "_meta": {
      "title": "Image Scale Down By"
    }
  },
  "193": {
    "inputs": {
      "base_image": [
        "192",
        0
      ]
    },
    "class_type": "GetResolutionForDepth",
    "_meta": {
      "title": "Get Resolution"
    }
  },
  "194": {
    "inputs": {
      "blend_factor": [
        "195",
        0
      ],
      "blend_mode": "normal",
      "image1": [
        "188",
        0
      ],
      "image2": [
        "192",
        0
      ]
    },
    "class_type": "ImageBlend",
    "_meta": {
      "title": "Image Blend"
    }
  },
  "195": {
    "inputs": {
      "value": 0.7000000000000001
    },
    "class_type": "PrimitiveFloat",
    "_meta": {
      "title": "BlendFactor"
    }
  },
  "196": {
    "inputs": {
      "value": 1920
    },
    "class_type": "PrimitiveFloat",
    "_meta": {
      "title": "SigmaResolution"
    }
  }
}
"""

def queue_prompt(prompt):
    p = {"prompt": prompt}

    # If the workflow contains API nodes, you can add a Comfy API key to the `extra_data`` field of the payload.
    # p["extra_data"] = {
    #     "api_key_comfy_org": "comfyui-87d01e28d*******************************************************"  # replace with real key
    # }
    # See: https://docs.comfy.org/tutorials/api-nodes/overview
    # Generate a key here: https://platform.comfy.org/login

    data = json.dumps(p).encode('utf-8')
    req =  request.Request("http://"+os.environ["COMFYUIHOST"]+":"+os.environ["COMFYUIPORT"]+"/prompt", data=data)
    request.urlopen(req)

      
if len(sys.argv) == 6 + 1:
    prompt = json.loads(prompt_text)
    prompt["183"]["inputs"]["image"] = sys.argv[1]
    prompt["185"]["inputs"]["filename_prefix"] = sys.argv[2] 
    prompt["168"]["inputs"]["model_name"] = sys.argv[3]
    prompt["186"]["inputs"]["value"] = float(sys.argv[4])
    prompt["195"]["inputs"]["value"] = float(sys.argv[5])
    prompt["196"]["inputs"]["value"] = float(sys.argv[6])
    
    queue_prompt(prompt)
else:
    print("Invalid arguments were given ("+ str(len(sys.argv)-1) +"). Usage: python " + sys.argv[0] + " InputVideoPath OutputPathPrefix upscalemodel scalefactor blendfactor sigmaresolution")

