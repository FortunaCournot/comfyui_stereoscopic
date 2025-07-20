#Copyright (c) 2025 FortunaCournot. MIT License.

import json
import sys
from urllib import request

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
      "count": 138
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
        "88",
        0
      ]
    },
    "class_type": "MathExpression|pysssss",
    "_meta": {
      "title": "Batch Count"
    }
  },
  "88": {
    "inputs": {
      "Number": "60"
    },
    "class_type": "Int",
    "_meta": {
      "title": "Frames per batch"
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
        "88",
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
  "115": {
    "inputs": {
      "images": [
        "69",
        0
      ]
    },
    "class_type": "easy imageListToImageBatch",
    "_meta": {
      "title": "Image List To Image Batch"
    }
  },
  "129": {
    "inputs": {
      "batched": [
        "115",
        0
      ]
    },
    "class_type": "VHS_Unbatch",
    "_meta": {
      "title": "Unbatch"
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
  "161": {
    "inputs": {
      "base_image": [
        "129",
        0
      ]
    },
    "class_type": "GetResolutionForDepth",
    "_meta": {
      "title": "Get Resolution"
    }
  },
  "162": {
    "inputs": {
      "ckpt_name": "depth_anything_v2_vitl.pth",
      "resolution": [
        "161",
        3
      ],
      "image": [
        "129",
        0
      ]
    },
    "class_type": "DepthAnythingV2Preprocessor",
    "_meta": {
      "title": "Depth Anything V2 - Relative"
    }
  },
  "163": {
    "inputs": {
      "depth_scale": 1,
      "depth_offset": 0,
      "switch_sides": false,
      "blur_radius": 45,
      "symetric": false,
      "processing": "Normal",
      "base_image": [
        "129",
        0
      ],
      "depth_image": [
        "162",
        0
      ]
    },
    "class_type": "ImageSBSConverter",
    "_meta": {
      "title": "Convert to Side-by-Side"
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
      "crf": 17,
      "save_metadata": true,
      "trim_to_audio": false,
      "pingpong": false,
      "save_output": true,
      "images": [
        "163",
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
      "title": "Math Expression 🐍"
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
    req =  request.Request("http://127.0.0.1:8188/prompt", data=data)
    request.urlopen(req)

if len(sys.argv) != 4 + 1:
   print("Invalid arguments were given ("+ str(len(sys.argv)-1) +"). Usage: python " + sys.argv[0] + " depth_scale depth_offset InputVideoPath OutputPathPrefix")
else:
    prompt = json.loads(prompt_text)
    prompt["163"]["inputs"]["depth_scale"] = float(sys.argv[1])
    prompt["163"]["inputs"]["depth_offset"] = float(sys.argv[2])
    prompt["163"]["inputs"]["blur_radius"] = int(45)
    prompt["159"]["inputs"]["value"] = sys.argv[3]
    prompt["160"]["inputs"]["value"] = sys.argv[4] 
    
    queue_prompt(prompt)

