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

def queue_prompt(prompt):
    response = requests.post("http://"+os.environ["COMFYUIHOST"]+":"+os.environ["COMFYUIPORT"]+"/prompt", json={"prompt": prompt})
    if response.status_code != 200:
        print(response.status_code, response.text)


if len(sys.argv) != 4 + 1:
   print("Invalid arguments were given ("+ str(len(sys.argv)-1) +"). Usage: python " + sys.argv[0] + " apifile StartImagePath OutputPathPrefix Prompt")
else:
    with open(sys.argv[1]) as f:
        prompt = json.load(f)

    prompt["59"]["inputs"]["image"] = sys.argv[2]
    prompt["30"]["inputs"]["value"] = sys.argv[3] 
    prompt["20"]["inputs"]["value"] = sys.argv[4]
    
    queue_prompt(prompt)

