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
      "value": ""
    },
    "class_type": "PrimitiveString",
    "_meta": {
      "title": "OutputPathPrefix"
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
  "174": {
    "inputs": {
      "value": 1
    },
    "class_type": "PrimitiveFloat",
    "_meta": {
      "title": "Downscale"
    }
  },
  "190": {
    "inputs": {
      "value": 1920
    },
    "class_type": "PrimitiveFloat",
    "_meta": {
      "title": "SigmaResolution (Normalizing constant)"
    }
  },
  "195": {
    "inputs": {
      "file": "",
      "video-preview": ""
    },
    "class_type": "LoadVideo",
    "_meta": {
      "title": "Load Video"
    }
  },
  "198": {
    "inputs": {
      "fps": [
        "200",
        2
      ],
      "images": [
        "214",
        0
      ],
      "audio": [
        "200",
        1
      ]
    },
    "class_type": "CreateVideo",
    "_meta": {
      "title": "Create Video"
    }
  },
  "199": {
    "inputs": {
      "filename_prefix": [
        "160",
        0
      ],
      "format": "mp4",
      "codec": "h264",
      "video-preview": "",
      "video": [
        "198",
        0
      ]
    },
    "class_type": "SaveVideo",
    "_meta": {
      "title": "Save Video"
    }
  },
  "200": {
    "inputs": {
      "video": [
        "195",
        0
      ]
    },
    "class_type": "GetVideoComponents",
    "_meta": {
      "title": "Get Video Components"
    }
  },
  "205": {
    "inputs": {
      "upscale_model": [
        "168",
        0
      ],
      "image": [
        "200",
        0
      ]
    },
    "class_type": "ImageUpscaleWithModel",
    "_meta": {
      "title": "Upscale Image (using Model)"
    }
  },
  "206": {
    "inputs": {
      "expression": "a / b",
      "a": [
        "207",
        3
      ],
      "b": [
        "190",
        0
      ]
    },
    "class_type": "MathExpression|pysssss",
    "_meta": {
      "title": "Normalize Sigma"
    }
  },
  "207": {
    "inputs": {
      "base_image": [
        "205",
        0
      ]
    },
    "class_type": "GetResolutionForVR",
    "_meta": {
      "title": "Get Resolution"
    }
  },
  "211": {
    "inputs": {
      "base_image": [
        "216",
        0
      ]
    },
    "class_type": "GetResolutionForVR",
    "_meta": {
      "title": "Get Resolution"
    }
  },
  "212": {
    "inputs": {
      "upscale_method": "nearest-exact",
      "width": [
        "211",
        0
      ],
      "height": [
        "211",
        1
      ],
      "crop": "disabled",
      "image": [
        "200",
        0
      ]
    },
    "class_type": "ImageScale",
    "_meta": {
      "title": "Upscale Image"
    }
  },
  "214": {
    "inputs": {
      "blend_factor": 0.8500000000000002,
      "blend_mode": "normal",
      "image1": [
        "212",
        0
      ],
      "image2": [
        "216",
        0
      ]
    },
    "class_type": "ImageBlend",
    "_meta": {
      "title": "Image Blend"
    }
  },
  "216": {
    "inputs": {
      "scale_by": [
        "174",
        0
      ],
      "images": [
        "220",
        0
      ]
    },
    "class_type": "easy imageScaleDownBy",
    "_meta": {
      "title": "Image Scale Down By"
    }
  },
  "220": {
    "inputs": {
      "sigmaX": [
        "206",
        1
      ],
      "sigmaY": [
        "206",
        1
      ],
      "image": [
        "205",
        0
      ]
    },
    "class_type": "Blur (mtb)",
    "_meta": {
      "title": "Blur (mtb)"
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
    prompt["195"]["inputs"]["file"] = sys.argv[1]
    prompt["199"]["inputs"]["filename_prefix"] = sys.argv[2] 
    prompt["168"]["inputs"]["model_name"] = sys.argv[3]
    prompt["174"]["inputs"]["value"] = float(sys.argv[4])
    prompt["214"]["inputs"]["blend_factor"] = float(sys.argv[5])
    prompt["190"]["inputs"]["value"] = float(sys.argv[6])
    #prompt["164"]["inputs"]["format"] = sys.argv[7] 
    #prompt["164"]["inputs"]["pix_fmt"] = sys.argv[8] 
    #prompt["164"]["inputs"]["crf"] = sys.argv[9] 
    
    queue_prompt(prompt)
else:
    # videoformat videopixfmt videocrf
    print("Invalid arguments were given ("+ str(len(sys.argv)-1) +"). Usage: python " + sys.argv[0] + " InputVideoPath OutputPathPrefix upscalemodel scalefactor blendfactor sigmaresolution ")

