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
  "3": {
    "inputs": {
      "seed": 176689519196660,
      "steps": 4,
      "cfg": 1,
      "sampler_name": "ddpm",
      "scheduler": "ddim_uniform",
      "denoise": 1,
      "model": [
        "48",
        0
      ],
      "positive": [
        "49",
        0
      ],
      "negative": [
        "49",
        1
      ],
      "latent_image": [
        "49",
        2
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
        "189",
        2
      ],
      "clip": [
        "185",
        1
      ]
    },
    "class_type": "CLIPTextEncode",
    "_meta": {
      "title": "CLIP Text Encode (Positive Prompt)"
    }
  },
  "7": {
    "inputs": {
      "text": "bad quality, blurry, messy, chaotic, (watermark:3), (text:3), (subtitle:3), score_6, score_5, score_4, censored, deformed, bad hand,  deformed face, low quality, bad quality, worst quality, (drawn, furry, illustration, cartoon, anime, comic:1.5), 3d, cgi, extra fingers, (source_anime, source_cartoon, source_furry, source_western, source_comic, source_pony), deformed teeth",
      "clip": [
        "185",
        1
      ]
    },
    "class_type": "CLIPTextEncode",
    "_meta": {
      "title": "CLIP Text Encode (Negative Prompt)"
    }
  },
  "8": {
    "inputs": {
      "samples": [
        "58",
        0
      ],
      "vae": [
        "152",
        0
      ]
    },
    "class_type": "VAEDecode",
    "_meta": {
      "title": "VAE Decode"
    }
  },
  "48": {
    "inputs": {
      "shift": 8.000000000000002,
      "model": [
        "207",
        0
      ]
    },
    "class_type": "ModelSamplingSD3",
    "_meta": {
      "title": "ModelSamplingSD3"
    }
  },
  "49": {
    "inputs": {
      "width": [
        "137",
        0
      ],
      "height": [
        "139",
        0
      ],
      "length": [
        "131",
        0
      ],
      "batch_size": 1,
      "strength": 1,
      "positive": [
        "6",
        0
      ],
      "negative": [
        "7",
        0
      ],
      "vae": [
        "152",
        0
      ],
      "control_video": [
        "110",
        0
      ],
      "control_masks": [
        "130",
        0
      ]
    },
    "class_type": "WanVaceToVideo",
    "_meta": {
      "title": "WanVaceToVideo"
    }
  },
  "58": {
    "inputs": {
      "trim_amount": [
        "49",
        3
      ],
      "samples": [
        "3",
        0
      ]
    },
    "class_type": "TrimVideoLatent",
    "_meta": {
      "title": "TrimVideoLatent"
    }
  },
  "68": {
    "inputs": {
      "fps": [
        "223",
        1
      ],
      "images": [
        "8",
        0
      ],
      "audio": [
        "197",
        2
      ]
    },
    "class_type": "CreateVideo",
    "_meta": {
      "title": "Create Video"
    }
  },
  "69": {
    "inputs": {
      "filename_prefix": "vr/outpaint/intermediate/result",
      "format": "mp4",
      "codec": "h264",
      "video": [
        "68",
        0
      ]
    },
    "class_type": "SaveVideo",
    "_meta": {
      "title": "Save Video"
    }
  },
  "110": {
    "inputs": {
      "left": [
        "218",
        0
      ],
      "top": [
        "213",
        0
      ],
      "right": [
        "218",
        0
      ],
      "bottom": [
        "217",
        0
      ],
      "feathering": 16,
      "image": [
        "197",
        0
      ]
    },
    "class_type": "ImagePadForOutpaint",
    "_meta": {
      "title": "Pad Image for Outpainting"
    }
  },
  "111": {
    "inputs": {
      "mask": [
        "110",
        1
      ]
    },
    "class_type": "MaskToImage",
    "_meta": {
      "title": "Convert Mask to Image"
    }
  },
  "129": {
    "inputs": {
      "amount": [
        "131",
        0
      ],
      "image": [
        "111",
        0
      ]
    },
    "class_type": "RepeatImageBatch",
    "_meta": {
      "title": "RepeatImageBatch"
    }
  },
  "130": {
    "inputs": {
      "channel": "red",
      "image": [
        "129",
        0
      ]
    },
    "class_type": "ImageToMask",
    "_meta": {
      "title": "Convert Image to Mask"
    }
  },
  "131": {
    "inputs": {
      "value": [
        "224",
        0
      ]
    },
    "class_type": "PrimitiveInt",
    "_meta": {
      "title": "Length"
    }
  },
  "137": {
    "inputs": {
      "value": 1280
    },
    "class_type": "PrimitiveInt",
    "_meta": {
      "title": "Width"
    }
  },
  "139": {
    "inputs": {
      "value": 720
    },
    "class_type": "PrimitiveInt",
    "_meta": {
      "title": "Height"
    }
  },
  "151": {
    "inputs": {
      "unet_name": "wan2.1_vace_14B_fp16.safetensors",
      "weight_dtype": "default"
    },
    "class_type": "UNETLoader",
    "_meta": {
      "title": "Load Diffusion Model"
    }
  },
  "152": {
    "inputs": {
      "vae_name": "wan_2.1_vae.safetensors"
    },
    "class_type": "VAELoader",
    "_meta": {
      "title": "Load VAE"
    }
  },
  "161": {
    "inputs": {
      "clip_name": "umt5_xxl_fp16.safetensors",
      "type": "wan",
      "device": "default"
    },
    "class_type": "CLIPLoader",
    "_meta": {
      "title": "Load CLIP"
    }
  },
  "185": {
    "inputs": {
      "PowerLoraLoaderHeaderWidget": {
        "type": "PowerLoraLoaderHeaderWidget"
      },
      "lora_1": {
        "on": true,
        "lora": "incoming\\new_tentacle_core-ILL_by_VisionaryAI.safetensors",
        "strength": 0.7
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
        "151",
        0
      ],
      "clip": [
        "161",
        0
      ]
    },
    "class_type": "Power Lora Loader (rgthree)",
    "_meta": {
      "title": "Power Lora Loader (rgthree)"
    }
  },
  "187": {
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
  "188": {
    "inputs": {
      "indexes": "0",
      "err_if_missing": true,
      "err_if_empty": true,
      "image": [
        "197",
        0
      ]
    },
    "class_type": "VHS_SelectImages",
    "_meta": {
      "title": "Select Images 🎥🅥🅗🅢"
    }
  },
  "189": {
    "inputs": {
      "text_input": "",
      "task": "detailed_caption",
      "fill_mask": false,
      "keep_model_loaded": false,
      "max_new_tokens": 1024,
      "num_beams": 3,
      "do_sample": false,
      "output_mask_select": "",
      "seed": 510729798263362,
      "image": [
        "188",
        0
      ],
      "florence2_model": [
        "187",
        0
      ]
    },
    "class_type": "Florence2Run",
    "_meta": {
      "title": "Florence2Run"
    }
  },
  "197": {
    "inputs": {
      "video": "test_video_outpaint (2).mp4",
      "force_rate": [
        "223",
        1
      ],
      "custom_width": 0,
      "custom_height": 0,
      "frame_load_cap": [
        "224",
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
  "207": {
    "inputs": {
      "lora_name": "Wan21_CausVid_14B_T2V_lora_rank32.safetensors",
      "strength_model": 0.7000000000000002,
      "model": [
        "185",
        0
      ]
    },
    "class_type": "LoraLoaderModelOnly",
    "_meta": {
      "title": "LoraLoaderModelOnly"
    }
  },
  "213": {
    "inputs": {
      "expression": "max(0, 720 - min(a,720)) * (( 1.0 - min(max(b,-1),1)) / 2.0)",
      "a": [
        "216",
        1
      ],
      "b": [
        "214",
        0
      ]
    },
    "class_type": "MathExpression|pysssss",
    "_meta": {
      "title": "top padding"
    }
  },
  "214": {
    "inputs": {
      "Number": "1"
    },
    "class_type": "Float",
    "_meta": {
      "title": "Vertical Alignment (Float) 1 is top -1 is bottom"
    }
  },
  "216": {
    "inputs": {
      "base_image": [
        "197",
        0
      ]
    },
    "class_type": "GetResolutionForVR",
    "_meta": {
      "title": "Resolution Info"
    }
  },
  "217": {
    "inputs": {
      "expression": "max(0, 720 - min(a,720)) * (( min(max(b,-1),1) + 1.0) / 2.0)",
      "a": [
        "216",
        1
      ],
      "b": [
        "214",
        0
      ]
    },
    "class_type": "MathExpression|pysssss",
    "_meta": {
      "title": "bottom padding"
    }
  },
  "218": {
    "inputs": {
      "expression": "max(0, 1280 - min(a,1280)) / 2.0",
      "a": [
        "216",
        0
      ]
    },
    "class_type": "MathExpression|pysssss",
    "_meta": {
      "title": "side padding"
    }
  },
  "222": {
    "inputs": {
      "value": 8
    },
    "class_type": "PrimitiveInt",
    "_meta": {
      "title": "FPS (Divisible by 4)"
    }
  },
  "223": {
    "inputs": {
      "expression": "a",
      "a": [
        "222",
        0
      ]
    },
    "class_type": "MathExpression|pysssss",
    "_meta": {
      "title": "ToFloat"
    }
  },
  "224": {
    "inputs": {
      "expression": "2 * a",
      "a": [
        "222",
        0
      ]
    },
    "class_type": "MathExpression|pysssss",
    "_meta": {
      "title": "x2"
    }
  }
}
"""

def queue_prompt(prompt):
    response = requests.post("http://"+os.environ["COMFYUIHOST"]+":"+os.environ["COMFYUIPORT"]+"/prompt", json={"prompt": prompt})
    if response.status_code != 200:
        print(response.status_code, response.text)


if len(sys.argv) != 5 + 1:
   print("Invalid arguments were given ("+ str(len(sys.argv)-1) +"). Usage: python " + sys.argv[0] + " depth_model_ckpt_name depth_scale depth_offset InputVideoPath OutputPathPrefix videoformat videopixfmt videocrf")
else:
    prompt = json.loads(prompt_text)
    prompt["175"]["inputs"]["ckpt_name"] = sys.argv[1]
    prompt["176"]["inputs"]["depth_scale"] = float(sys.argv[2])
    prompt["176"]["inputs"]["depth_offset"] = float(sys.argv[3])
    prompt["176"]["inputs"]["blur_radius"] = int(45)
    prompt["171"]["inputs"]["file"] = sys.argv[4]
    prompt["177"]["inputs"]["filename_prefix"] = sys.argv[5] 
    #prompt["164"]["inputs"]["format"] = sys.argv[6] 
    #prompt["164"]["inputs"]["pix_fmt"] = sys.argv[7] 
    #prompt["164"]["inputs"]["crf"] = sys.argv[8] 
    
    queue_prompt(prompt)

