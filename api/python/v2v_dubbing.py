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
  "73": {
    "inputs": {
      "video_info": [
        "178",
        3
      ]
    },
    "class_type": "VHS_VideoInfo",
    "_meta": {
      "title": "Video Info"
    }
  },
  "169": {
    "inputs": {
      "mmaudio_model": "mmaudio_large_44k_v2_fp16.safetensors",
      "base_precision": "fp16"
    },
    "class_type": "MMAudioModelLoader",
    "_meta": {
      "title": "MMAudio ModelLoader"
    }
  },
  "170": {
    "inputs": {
      "vae_model": "mmaudio_vae_44k_fp16.safetensors",
      "synchformer_model": "mmaudio_synchformer_fp16.safetensors",
      "clip_model": "apple_DFN5B-CLIP-ViT-H-14-384_fp16.safetensors",
      "mode": "44k",
      "precision": "fp16"
    },
    "class_type": "MMAudioFeatureUtilsLoader",
    "_meta": {
      "title": "MMAudio FeatureUtilsLoader"
    }
  },
  "171": {
    "inputs": {
      "duration": [
        "73",
        7
      ],
      "steps": 25,
      "cfg": 6,
      "seed": 249391616827393,
      "prompt": [
        "193",
        0
      ],
      "negative_prompt": [
        "195",
        0
      ],
      "mask_away_clip": false,
      "force_offload": true,
      "mmaudio_model": [
        "169",
        0
      ],
      "feature_utils": [
        "170",
        0
      ],
      "images": [
        "178",
        0
      ]
    },
    "class_type": "MMAudioSampler",
    "_meta": {
      "title": "MMAudio Sampler"
    }
  },
  "172": {
    "inputs": {
      "text_input": "",
      "task": "more_detailed_caption",
      "fill_mask": false,
      "keep_model_loaded": false,
      "max_new_tokens": 4096,
      "num_beams": 3,
      "do_sample": false,
      "output_mask_select": "",
      "seed": 554639759133520,
      "image": [
        "182",
        0
      ],
      "florence2_model": [
        "198",
        0
      ]
    },
    "class_type": "Florence2Run",
    "_meta": {
      "title": "Florence2Run"
    }
  },
  "174": {
    "inputs": {
      "filename_prefix": "audio/ComfyUI",
      "audioUI": "",
      "audio": [
        "171",
        0
      ]
    },
    "class_type": "SaveAudio",
    "_meta": {
      "title": "Output - Save Audio"
    }
  },
  "178": {
    "inputs": {
      "video": "88968441.mp4",
      "force_rate": 25,
      "custom_width": 0,
      "custom_height": 0,
      "frame_load_cap": [
        "192",
        0
      ],
      "skip_first_frames": 0,
      "select_every_nth": 1,
      "format": "None"
    },
    "class_type": "VHS_LoadVideo",
    "_meta": {
      "title": "Input - Load Video"
    }
  },
  "182": {
    "inputs": {
      "batch_index": [
        "184",
        0
      ],
      "length": 1,
      "image": [
        "178",
        0
      ]
    },
    "class_type": "ImageFromBatch",
    "_meta": {
      "title": "ImageFromBatch"
    }
  },
  "184": {
    "inputs": {
      "expression": "a/3",
      "a": [
        "73",
        6
      ]
    },
    "class_type": "MathExpression|pysssss",
    "_meta": {
      "title": "Math Expression"
    }
  },
  "191": {
    "inputs": {
      "value": 8
    },
    "class_type": "PrimitiveInt",
    "_meta": {
      "title": "Input - AudioLength"
    }
  },
  "192": {
    "inputs": {
      "expression": "min(a,8)*25",
      "a": [
        "191",
        0
      ]
    },
    "class_type": "MathExpression|pysssss",
    "_meta": {
      "title": "Math Expression"
    }
  },
  "193": {
    "inputs": {
      "string_a": [
        "172",
        2
      ],
      "string_b": [
        "194",
        0
      ],
      "delimiter": " "
    },
    "class_type": "StringConcatenate",
    "_meta": {
      "title": "Concatenate"
    }
  },
  "194": {
    "inputs": {
      "file_path": "",
      "dictionary_name": "[filename]"
    },
    "class_type": "Load Text File",
    "_meta": {
      "title": "Input - Load Text File - Positive"
    }
  },
  "195": {
    "inputs": {
      "file_path": "",
      "dictionary_name": "[filename]"
    },
    "class_type": "Load Text File",
    "_meta": {
      "title": "Input - Load Text File - Negative"
    }
  },
  "198": {
    "inputs": {
      "model": "microsoft/Florence-2-base",
      "precision": "fp16",
      "attention": "sdpa",
      "convert_to_safetensors": false
    },
    "class_type": "DownloadAndLoadFlorence2Model",
    "_meta": {
      "title": "DownloadAndLoadFlorence2Model"
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

      
if len(sys.argv) == 1 + 6:
    prompt = json.loads(prompt_text)
    prompt["178"]["inputs"]["video"] = sys.argv[1]
    prompt["174"]["inputs"]["filename_prefix"] = sys.argv[2] 
    prompt["191"]["inputs"]["value"] = int(sys.argv[3])
    prompt["194"]["inputs"]["file_path"] = sys.argv[4]
    prompt["195"]["inputs"]["file_path"] = sys.argv[5]
    prompt["198"]["inputs"]["model"] = sys.argv[6]
    
    queue_prompt(prompt)
else:
    print("Invalid arguments were given ("+ str(len(sys.argv)-1) +"). Usage: python " + sys.argv[0] + " InputVideoPath OutputPathPrefix AudioLength PositivePromptTextfile NegativePromptTextfile florence2model")

