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
      "video": "",
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
      "title": "Load Video"
    }
  },
  "73": {
    "inputs": {
      "video_info": [
        "69",
        3
      ]
    },
    "class_type": "VHS_VideoInfo",
    "_meta": {
      "title": "Video Info"
    }
  },
  "164": {
    "inputs": {
      "frame_rate": [
        "73",
        0
      ],
      "loop_count": 0,
      "filename_prefix": "dub",
      "format": "video/h264-mp4",
      "pix_fmt": "yuv420p",
      "crf": 17,
      "save_metadata": true,
      "trim_to_audio": false,
      "pingpong": false,
      "save_output": true,
      "images": [
        "69",
        0
      ],
      "audio": [
        "171",
        0
      ]
    },
    "class_type": "VHS_VideoCombine",
    "_meta": {
      "title": "Video Combine"
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
        2
      ],
      "steps": 25,
      "cfg": 6,
      "seed": 0,
      "prompt": [
        "172",
        2
      ],
      "negative_prompt": "",
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
        "69",
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
      "max_new_tokens": 1024,
      "num_beams": 3,
      "do_sample": false,
      "output_mask_select": "",
      "seed": 60622919171493,
      "image": [
        "69",
        0
      ],
      "florence2_model": [
        "173",
        0
      ]
    },
    "class_type": "Florence2Run",
    "_meta": {
      "title": "Florence2Run"
    }
  },
  "173": {
    "inputs": {
      "model": "Florence-2-base",
      "precision": "fp16",
      "attention": "sdpa",
      "convert_to_safetensors": false
    },
    "class_type": "Florence2ModelLoader",
    "_meta": {
      "title": "Florence2ModelLoader"
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

      
if len(sys.argv) == 2 + 1:
    prompt = json.loads(prompt_text)
    prompt["69"]["inputs"]["video"] = sys.argv[1]
    prompt["164"]["inputs"]["filename_prefix"] = sys.argv[2] 
    prompt["164"]["inputs"]["crf"] = 17
    
    queue_prompt(prompt)
else:
    print("Invalid arguments were given ("+ str(len(sys.argv)-1) +"). Usage: python " + sys.argv[0] + " InputVideoPath OutputPathPrefix")

