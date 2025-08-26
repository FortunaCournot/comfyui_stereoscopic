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
      "seed": 730341091025363,
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
  "178": {
    "inputs": {
      "video": "VR-we-are-RAW1.mp4",
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
      "title": "Input - MaxScanLength"
    }
  },
  "192": {
    "inputs": {
      "expression": "min(a,128)*25",
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
  "198": {
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
  "205": {
    "inputs": {
      "text_input": "",
      "task": "ocr",
      "fill_mask": false,
      "keep_model_loaded": false,
      "max_new_tokens": 4096,
      "num_beams": 3,
      "do_sample": false,
      "output_mask_select": "",
      "seed": 730341091025363,
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
  "206": {
    "inputs": {
      "root_dir": "output",
      "file": "vr/caption/intermediate/temp_ocr.txt",
      "append": "overwrite",
      "insert": true,
      "text": [
        "205",
        2
      ]
    },
    "class_type": "SaveText|pysssss",
    "_meta": {
      "title": "Save Caption"
    }
  },
  "207": {
    "inputs": {
      "root_dir": "output",
      "file": "vr/caption/intermediate/temp_caption.txt",
      "append": "overwrite",
      "insert": true,
      "text": [
        "172",
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



if len(sys.argv) == 3 + 1:
    prompt = json.loads(prompt_text)
    
    prompt["178"]["inputs"]["video"] = sys.argv[1]  # path relative to input folder
    #prompt["207"]["inputs"]["file"] = sys.argv[2] + '/temp_caption.txt'
    #prompt["206"]["inputs"]["file"] = sys.argv[2] + '/temp_ocr.txt'
    prompt["172"]["inputs"]["task"] = sys.argv[3]
    
    prompt["191"]["inputs"]["value"] = 8
    prompt["198"]["inputs"]["model"] = "microsoft/Florence-2-base"
    prompt["198"]["inputs"]["precision"] = "fp16"
    
    queue_prompt(prompt)
else:
    print("Invalid arguments were given ("+ str(len(sys.argv)-1) +"). Usage: python " + sys.argv[0] + " InputImagePath TextOutputFolderPath florencerun_task")

