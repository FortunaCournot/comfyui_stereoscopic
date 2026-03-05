#Copyright (c) 2026 Fortuna Cournot. MIT License. www.3d-gallery.org

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

def queue_prompt(prompt):
    response = requests.post("http://"+os.environ["COMFYUIHOST"]+":"+os.environ["COMFYUIPORT"]+"/prompt", json={"prompt": prompt})
    if response.status_code != 200:
        print(response.status_code, response.text)


def load_json_file(path: str):
    """Load JSON with sane encodings (ComfyUI API exports are typically UTF-8).

    Windows' default cp1252 can throw on bytes like 0x90, so we try UTF-8 first.
    """
    last_error = None
    for enc in ("utf-8-sig", "utf-8", "cp1252", "latin-1"):
        try:
            with open(path, "r", encoding=enc) as f:
                return json.load(f)
        except (UnicodeDecodeError, json.JSONDecodeError) as e:
            last_error = e
    raise last_error


if len(sys.argv) != 6 + 1 and len(sys.argv) != 7 + 1:
   print("Invalid arguments were given ("+ str(len(sys.argv)-1) +"). Usage: python " + sys.argv[0] + " apifile StartImagePath ControlVideoPath OutputPathPrefix Length Prompt [ColorImagePath]")
else:
    try:
        prompt = load_json_file(sys.argv[1])
    except Exception as e:
        print(f"Error: failed to load api JSON '{sys.argv[1]}': {e}")
        sys.exit(1)

    try:
        prompt["178"]["inputs"]["image"] = sys.argv[2]
        prompt["174"]["inputs"]["file"] = sys.argv[3]
        prompt["195"]["inputs"]["value"] = sys.argv[4]
        prompt["193"]["inputs"]["value"] = sys.argv[5]
        prompt["194"]["inputs"]["value"] = sys.argv[6]
        prompt["217"]["inputs"]["blend_factor"] = "0.10"
        if len(sys.argv) == 8:
            prompt["220"]["inputs"]["image"] = sys.argv[7]
        else:
            prompt["178"]["inputs"]["image"] = sys.argv[2]
    except Exception as e:
        print(f"Error: unexpected API graph structure (node missing?): {e}")
        sys.exit(1)

    queue_prompt(prompt)

