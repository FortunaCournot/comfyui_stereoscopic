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
  "69": {
    "inputs": {
      "video": [
        "159",
        0
      ],
      "force_rate": 0,
      "custom_width": 0,
      "custom_height": 0,
      "frame_load_cap": 0,
      "skip_first_frames": [
        "92",
        0
      ],
      "select_every_nth": 1,
      "format": "None",
      "meta_batch": [
        "70",
        0
      ]
    },
    "class_type": "VHS_LoadVideoPath",
    "_meta": {
      "title": "Load Video"
    }
  },
  "70": {
    "inputs": {
      "frames_per_batch": [
        "91",
        0
      ],
      "count": 139
    },
    "class_type": "VHS_BatchManager",
    "_meta": {
      "title": "Meta Batch Manager"
    }
  },
  "73": {
    "inputs": {
      "video_info": [
        "105",
        3
      ]
    },
    "class_type": "VHS_VideoInfo",
    "_meta": {
      "title": "Video Info"
    }
  },
  "87": {
    "inputs": {
      "expression": "(a + b - 1) / b",
      "a": [
        "73",
        1
      ],
      "b": [
        "183",
        0
      ]
    },
    "class_type": "MathExpression|pysssss",
    "_meta": {
      "title": "Batch Count"
    }
  },
  "90": {
    "inputs": {
      "from_this": 1,
      "to_that": [
        "87",
        0
      ],
      "jump": 1
    },
    "class_type": "Bjornulf_LoopInteger",
    "_meta": {
      "title": "Loop (Integer)"
    }
  },
  "91": {
    "inputs": {
      "expression": "b",
      "a": [
        "90",
        0
      ],
      "b": [
        "183",
        0
      ]
    },
    "class_type": "MathExpression|pysssss",
    "_meta": {
      "title": "Loop Body Trigger Node"
    }
  },
  "92": {
    "inputs": {
      "expression": "(a - 1) * b",
      "a": [
        "90",
        0
      ],
      "b": [
        "87",
        0
      ]
    },
    "class_type": "MathExpression|pysssss",
    "_meta": {
      "title": "Loop: Skip Offset"
    }
  },
  "105": {
    "inputs": {
      "video": [
        "159",
        0
      ],
      "force_rate": 0,
      "custom_width": 0,
      "custom_height": 0,
      "frame_load_cap": 0,
      "skip_first_frames": 0,
      "select_every_nth": 1,
      "format": "None"
    },
    "class_type": "VHS_LoadVideoPath",
    "_meta": {
      "title": "Pre-Load Video (Path) for Info"
    }
  },
  "135": {
    "inputs": {
      "expression": "a + 0.1",
      "a": [
        "73",
        0
      ]
    },
    "class_type": "MathExpression|pysssss",
    "_meta": {
      "title": "Float2Int"
    }
  },
  "159": {
    "inputs": {
      "value": ""
    },
    "class_type": "PrimitiveString",
    "_meta": {
      "title": "InputVideoPath"
    }
  },
  "160": {
    "inputs": {
      "value": ""
    },
    "class_type": "PrimitiveString",
    "_meta": {
      "title": "OutputPathPrefix"
    }
  },
  "164": {
    "inputs": {
      "frame_rate": [
        "166",
        1
      ],
      "loop_count": 0,
      "filename_prefix": [
        "160",
        0
      ],
      "format": "video/h264-mp4",
      "pix_fmt": "yuv420p",
      "crf": 19,
      "save_metadata": true,
      "trim_to_audio": false,
      "pingpong": false,
      "save_output": true,
      "images": [
        "172",
        0
      ],
      "audio": [
        "105",
        2
      ]
    },
    "class_type": "VHS_VideoCombine",
    "_meta": {
      "title": "Video Combine"
    }
  },
  "166": {
    "inputs": {
      "expression": "a",
      "a": [
        "135",
        0
      ]
    },
    "class_type": "MathExpression|pysssss",
    "_meta": {
      "title": "Math Expression"
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
  "169": {
    "inputs": {
      "upscale_model": [
        "168",
        0
      ],
      "image": [
        "182",
        0
      ]
    },
    "class_type": "ImageUpscaleWithModel",
    "_meta": {
      "title": "Upscale Image (using Model)"
    }
  },
  "172": {
    "inputs": {
      "sigmaX": [
        "174",
        0
      ],
      "sigmaY": [
        "174",
        0
      ],
      "image": [
        "169",
        0
      ]
    },
    "class_type": "Blur (mtb)",
    "_meta": {
      "title": "Blur (mtb)"
    }
  },
  "174": {
    "inputs": {
      "value": 1
    },
    "class_type": "PrimitiveFloat",
    "_meta": {
      "title": "Sigma"
    }
  },
  "182": {
    "inputs": {
      "scale_by": 0.25000000000000006,
      "images": [
        "69",
        0
      ]
    },
    "class_type": "easy imageScaleDownBy",
    "_meta": {
      "title": "Image Scale Down By"
    }
  },
  "183": {
    "inputs": {
      "value": 60
    },
    "class_type": "PrimitiveInt",
    "_meta": {
      "title": "Max Frames per batch"
    }
  }
}
"""

def queue_prompt(prompt):
    response = requests.post("http://"+os.environ["COMFYUIHOST"]+":"+os.environ["COMFYUIPORT"]+"/prompt", json={"prompt": prompt})
    if response.status_code != 200:
        print(response.status_code, response.text)



if len(sys.argv) == 2 + 1:
    prompt = json.loads(prompt_text)
    prompt["159"]["inputs"]["value"] = sys.argv[1]
    prompt["160"]["inputs"]["value"] = sys.argv[2] 
    prompt["174"]["inputs"]["value"] = 1.0
    prompt["168"]["inputs"]["model_name"] = "RealESRGAN_x2.pth"
    prompt["164"]["inputs"]["format"] = "video/h264-mp4"
    prompt["164"]["inputs"]["pix_fmt"] = "yuv420p"
    prompt["164"]["inputs"]["crf"] = 17
    
    queue_prompt(prompt)
elif len(sys.argv) == 3 + 1:
    prompt = json.loads(prompt_text)
    prompt["159"]["inputs"]["value"] = sys.argv[1]
    prompt["160"]["inputs"]["value"] = sys.argv[2] 
    prompt["174"]["inputs"]["value"] = sys.argv[3]
    prompt["168"]["inputs"]["model_name"] = "RealESRGAN_x2.pth"
    prompt["164"]["inputs"]["format"] = "video/h264-mp4"
    prompt["164"]["inputs"]["pix_fmt"] = "yuv420p"
    prompt["164"]["inputs"]["crf"] = 17
    
    queue_prompt(prompt)
else:
    print("Invalid arguments were given ("+ str(len(sys.argv)-1) +"). Usage: python " + sys.argv[0] + " InputVideoPath OutputPathPrefix [sigma]")

