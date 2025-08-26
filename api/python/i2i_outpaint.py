#Copyright (c) 2025 Fortuna Cournot. MIT License. www.3d-gallery.org

import json
import sys
import requests
import os
import random

#This is the ComfyUI api prompt format.

#If you want it for a specific workflow you can "enable dev mode options"
#in the settings of the UI (gear beside the "Queue Size: ") this will enable
#a button on the UI to save workflows in api format.

#keep in mind ComfyUI is pre alpha software so this format will change a bit.

#this is the one for the default workflow
prompt_text = """
{
  "3": {
    "inputs": {
      "seed": 745193682211719,
      "steps": 20,
      "cfg": 10,
      "sampler_name": "euler_ancestral",
      "scheduler": "karras",
      "denoise": 0.9000000000000001,
      "model": [
        "35",
        0
      ],
      "positive": [
        "6",
        0
      ],
      "negative": [
        "7",
        0
      ],
      "latent_image": [
        "26",
        0
      ]
    },
    "class_type": "KSampler",
    "_meta": {
      "title": "KSampler"
    }
  },
  "6": {
    "inputs": {
      "text": [
        "41",
        2
      ],
      "clip": [
        "35",
        1
      ]
    },
    "class_type": "CLIPTextEncode",
    "_meta": {
      "title": "CLIP Text Encode (Prompt)"
    }
  },
  "7": {
    "inputs": {
      "text": "watermark, text",
      "clip": [
        "35",
        1
      ]
    },
    "class_type": "CLIPTextEncode",
    "_meta": {
      "title": "CLIP Text Encode (Prompt)"
    }
  },
  "8": {
    "inputs": {
      "samples": [
        "3",
        0
      ],
      "vae": [
        "29",
        2
      ]
    },
    "class_type": "VAEDecode",
    "_meta": {
      "title": "VAE Decode"
    }
  },
  "9": {
    "inputs": {
      "filename_prefix": "ComfyUI",
      "images": [
        "8",
        0
      ]
    },
    "class_type": "SaveImage",
    "_meta": {
      "title": "Save Image"
    }
  },
  "20": {
    "inputs": {
      "image": "test_image.png"
    },
    "class_type": "LoadImage",
    "_meta": {
      "title": "Load Image"
    }
  },
  "26": {
    "inputs": {
      "grow_mask_by": 64,
      "pixels": [
        "30",
        0
      ],
      "vae": [
        "29",
        2
      ],
      "mask": [
        "30",
        1
      ]
    },
    "class_type": "VAEEncodeForInpaint",
    "_meta": {
      "title": "VAE Encode (for Inpainting)"
    }
  },
  "29": {
    "inputs": {
      "ckpt_name": "512-inpainting-ema.safetensors"
    },
    "class_type": "CheckpointLoaderSimple",
    "_meta": {
      "title": "Load Checkpoint"
    }
  },
  "30": {
    "inputs": {
      "left": [
        "44",
        0
      ],
      "top": [
        "47",
        0
      ],
      "right": [
        "44",
        0
      ],
      "bottom": [
        "45",
        0
      ],
      "feathering": 0,
      "image": [
        "20",
        0
      ]
    },
    "class_type": "ImagePadForOutpaint",
    "_meta": {
      "title": "Pad Image for Outpainting"
    }
  },
  "35": {
    "inputs": {
      "PowerLoraLoaderHeaderWidget": {
        "type": "PowerLoraLoaderHeaderWidget"
      },
      "lora_1": {
        "on": false,
        "lora": "None",
        "strength": 0
      },
      "lora_2": {
        "on": false,
        "lora": "None",
        "strength": 0
      },
      "lora_3": {
        "on": false,
        "lora": "None",
        "strength": 0
      },
      "lora_4": {
        "on": false,
        "lora": "None",
        "strength": 0
      },
      "lora_5": {
        "on": false,
        "lora": "None",
        "strength": 0
      },
      "lora_6": {
        "on": false,
        "lora": "None",
        "strength": 0
      },
      "lora_7": {
        "on": false,
        "lora": "None",
        "strength": 0
      },
      "lora_8": {
        "on": false,
        "lora": "None",
        "strength": 0
      },
      "lora_9": {
        "on": false,
        "lora": "None",
        "strength": 0
      },
      "➕ Add Lora": "",
      "model": [
        "29",
        0
      ],
      "clip": [
        "29",
        1
      ]
    },
    "class_type": "Power Lora Loader (rgthree)",
    "_meta": {
      "title": "Power Lora Loader (rgthree)"
    }
  },
  "39": {
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
  },
  "41": {
    "inputs": {
      "text_input": "",
      "task": "more_detailed_caption",
      "fill_mask": false,
      "keep_model_loaded": false,
      "max_new_tokens": 1024,
      "num_beams": 3,
      "do_sample": false,
      "output_mask_select": "",
      "seed": 483302499167365,
      "image": [
        "20",
        0
      ],
      "florence2_model": [
        "39",
        0
      ]
    },
    "class_type": "Florence2Run",
    "_meta": {
      "title": "Florence2Run"
    }
  },
  "43": {
    "inputs": {
      "base_image": [
        "20",
        0
      ]
    },
    "class_type": "GetResolutionForVR",
    "_meta": {
      "title": "Resolution Info"
    }
  },
  "44": {
    "inputs": {
      "expression": "max(0, 1280 - min(a,1280)) / 2.0",
      "a": [
        "43",
        0
      ]
    },
    "class_type": "MathExpression|pysssss",
    "_meta": {
      "title": "side padding"
    }
  },
  "45": {
    "inputs": {
      "expression": "max(0, 720 - min(a,720)) * ((min(max(b,-1),1) + 1.0 ) / 2.0)",
      "a": [
        "43",
        1
      ],
      "b": [
        "46",
        0
      ]
    },
    "class_type": "MathExpression|pysssss",
    "_meta": {
      "title": "bottom padding"
    }
  },
  "46": {
    "inputs": {
      "Number": "1.0"
    },
    "class_type": "Float",
    "_meta": {
      "title": "Vertical Alignment (Float) 1 is top -1 is bottom"
    }
  },
  "47": {
    "inputs": {
      "expression": "max(0, 720 - min(a,720)) * (( 1.0 - min(max(b,-1),1) ) / 2.0)",
      "a": [
        "43",
        1
      ],
      "b": [
        "46",
        0
      ]
    },
    "class_type": "MathExpression|pysssss",
    "_meta": {
      "title": "top padding"
    }
  }
}
"""

def queue_prompt(prompt):
    response = requests.post("http://"+os.environ["COMFYUIHOST"]+":"+os.environ["COMFYUIPORT"]+"/prompt", json={"prompt": prompt})
    if response.status_code != 200:
        print(response.status_code, response.text)



if len(sys.argv) != 3 + 1:
   print("Invalid arguments were given ("+ str(len(sys.argv)-1) +"). Usage: python " + sys.argv[0] + " InputImagePath OutputPathPrefix NegativePromptTextfile")
else:
    with open(sys.argv[3], "r") as file:
        negative = file.read().replace("\n", " ")

    prompt["7"]["inputs"]["text"] = negative
    
    random_seed = random.randint(0,2147483647)
    prompt["3"]["inputs"]["seed"] = random_seed
    prompt["41"]["inputs"]["seed"] = random_seed
    
    prompt = json.loads(prompt_text)
    prompt["20"]["inputs"]["image"] = sys.argv[1]
    prompt["9"]["inputs"]["filename_prefix"] = sys.argv[2] 
    
    queue_prompt(prompt)

