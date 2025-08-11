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
  "2": {
    "inputs": {
      "text_input": "",
      "task": "more_detailed_caption",
      "fill_mask": false,
      "keep_model_loaded": true,
      "max_new_tokens": 4096,
      "num_beams": 3,
      "do_sample": false,
      "output_mask_select": "",
      "seed": 441010814110607,
      "image": [
        "12",
        0
      ],
      "florence2_model": [
        "8",
        0
      ]
    },
    "class_type": "Florence2Run",
    "_meta": {
      "title": "Florence2Run"
    }
  },
  "8": {
    "inputs": {
      "model": "microsoft/Florence-2-base",
      "precision": "fp16",
      "attention": "sdpa",
      "convert_to_safetensors": true
    },
    "class_type": "DownloadAndLoadFlorence2Model",
    "_meta": {
      "title": "DownloadAndLoadFlorence2Model"
    }
  },
  "12": {
    "inputs": {
      "image": "91200655.png"
    },
    "class_type": "LoadImage",
    "_meta": {
      "title": "Load Image"
    }
  },
  "15": {
    "inputs": {
      "text_input": "",
      "task": "ocr",
      "fill_mask": false,
      "keep_model_loaded": true,
      "max_new_tokens": 512,
      "num_beams": 3,
      "do_sample": false,
      "output_mask_select": "",
      "seed": 851977108039789,
      "image": [
        "12",
        0
      ],
      "florence2_model": [
        "8",
        0
      ]
    },
    "class_type": "Florence2Run",
    "_meta": {
      "title": "Florence2Run"
    }
  },
  "20": {
    "inputs": {
      "root_dir": "output",
      "file": "vr/caption/intermediate/temp_caption_long.txt",
      "append": "overwrite",
      "insert": true,
      "text": [
        "2",
        2
      ]
    },
    "class_type": "SaveText|pysssss",
    "_meta": {
      "title": "Save Caption"
    }
  },
  "21": {
    "inputs": {
      "root_dir": "output",
      "file": "vr/caption/intermediate/temp_ocr.txt",
      "append": "overwrite",
      "insert": true,
      "text": [
        "15",
        2
      ]
    },
    "class_type": "SaveText|pysssss",
    "_meta": {
      "title": "Save Caption"
    }
  },
  "22": {
    "inputs": {
      "text_input": "",
      "task": "caption",
      "fill_mask": false,
      "keep_model_loaded": true,
      "max_new_tokens": 2048,
      "num_beams": 3,
      "do_sample": false,
      "output_mask_select": "",
      "seed": 757524996186607,
      "image": [
        "12",
        0
      ],
      "florence2_model": [
        "8",
        0
      ]
    },
    "class_type": "Florence2Run",
    "_meta": {
      "title": "Florence2Run"
    }
  },
  "23": {
    "inputs": {
      "root_dir": "output",
      "file": "vr/caption/intermediate/temp_caption_short.txt",
      "append": "overwrite",
      "insert": true,
      "text": [
        "22",
        2
      ]
    },
    "class_type": "SaveText|pysssss",
    "_meta": {
      "title": "Save Caption"
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
    prompt["12"]["inputs"]["image"] = sys.argv[1]   # cwd  is input. path must start with vr/...
    prompt["2"]["inputs"]["task"] = sys.argv[2]

    prompt["8"]["inputs"]["model"] = "microsoft/Florence-2-base"
    prompt["8"]["inputs"]["precision"] = "fp16"
    
    queue_prompt(prompt)
else:
    print("Invalid arguments were given ("+ str(len(sys.argv)-1) +"). Usage: python " + sys.argv[0] + " InputImagePath florence2run_task")

