import os
import re

path = os.path.dirname(os.path.abspath(__file__))

# define stages
STAGES = ["caption", "scaling", "fullsbs", "interpolate", "singleloop", "dubbing/sfx", "slides", "slideshow", "watermark/encrypt", "watermark/decrypt", "concat", ]
subfolder = os.path.join(path, "../../../../custom_nodes/comfyui_stereoscopic/config/tasks")
if os.path.exists(subfolder):
    onlyfiles = next(os.walk(subfolder))[2]
    for f in onlyfiles:
        fl=f.lower()
        if fl.endswith(".json"):
            STAGES.append("tasks/" + fl[:-5])
subfolder = os.path.join(path, "../../../../user/default/comfyui_stereoscopic/tasks")
if os.path.exists(subfolder):
    onlyfiles = next(os.walk(subfolder))[2]
    for f in onlyfiles:
        fl=f.lower()
        if fl.endswith(".json"):
            STAGES.append("tasks/_" + fl[:-5])


# generate UML definition
uml_folder = os.path.join(path, "../../../../user/default/comfyui_stereoscopic/uml")
os.makedirs(uml_folder, exist_ok=True)
uml_def = os.path.join(uml_folder, "autoforward.uml")
with open(uml_def, "w") as f:
    f.write("' This file is generated - do not edit.\n")
    f.write("\n")
    f.write("@startuml\n")
    f.write("' Indicate the direction of the flowchart\n")
    f.write("left to right direction\n")
    f.write("title\n")
    f.write("<i>VR We Are</i> Pipeline\n")
    f.write("end title\n")
    f.write("\n")
    
    # scan stage forward rules to find state starts and ends
    targets=[]
    involved=[]
    startsCand=[]
    transitionRules=[]
    typeDef=[]
    for s in range(len(STAGES)):
        stage=STAGES[s]
        
        if re.match(r"tasks/_.*", stage):
            stageDefRes="user/default/comfyui_stereoscopic/tasks/" + stage[7:] + ".json"
        elif re.match(r"tasks/.*", stage):
            stageDefRes="custom_nodes/comfyui_stereoscopic/config/tasks/" + stage[6:] + ".json"
        else:
            stageDefRes="custom_nodes/comfyui_stereoscopic/config/stages/" + stage + ".json"

        type = ""
        defFile = os.path.join(path, "../../../../" + stageDefRes)
        if os.path.exists(defFile):
            with open(defFile) as file:
                deflines = [line.rstrip() for line in file]
                for line in range(len(deflines)):
                    inputMatch=re.match(r".*\"input\":", deflines[line])
                    if inputMatch:
                        valuepart=deflines[line][inputMatch.end():]
                        match = re.search(r"\".*\"", valuepart)
                        if match:
                            type = " : " + valuepart[match.start()+1:match.end()][:-1]
                        else:
                            type = ""
        match = re.search(r";", type)
        if match:
            type=""
        typeDef.append(type)
        
        forwarddef = os.path.join(path, "../../../../output/vr/" + stage + "/forward.txt")
        if os.path.exists(forwarddef):
            startsCand.append(s)
            if not s in involved:
                involved.append(s)
            with open(forwarddef) as file:
                rules = [line.rstrip() for line in file]
                for r in range(len(rules)):
                    rule=rules[r]
                    if not rule:
                        continue
                    if rule[0] == "#":
                        continue
                    options=""
                    stage=rule
                    match = re.match(r"\[.*\]", rule)
                    if match:
                        options=" : " + rule[match.start()+1:match.end()-1]
                        stage=rule[match.end()::]
                    sidx=STAGES.index(stage)
                    if sidx >=0 :
                        if not sidx in involved:
                            involved.append(sidx)
                        targets.append(sidx)
                        transitionRules.append("stage" + str(s) + " --> stage" + str(sidx) + options)

    f.write("' Aliases\n")
    #for s in involved:
    for s in involved:
        stage=STAGES[s]
        f.write("state \"" + stage + "\" as stage" + str(s) + typeDef[s] + "\n")
    f.write("\n")

     
    f.write("' Starts\n")
    for s in startsCand:
        stage=STAGES[s]
        if not s in targets:
            f.write("[*] --> stage" + str(s) + "\n")
    f.write("\n")

    f.write("' Transitions\n")
    for t in transitionRules:
        f.write(t + "\n")
    f.write("\n")
 
    f.write("' True Ends\n")
    for s in involved:
        stage=STAGES[s]
        if not s in startsCand:
            f.write("stage" + str(s) + " --> [*]\n")
    f.write("\n")

    f.write("@enduml\n")

