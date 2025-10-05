import os
import re

path = os.path.dirname(os.path.abspath(__file__))

# define stages
STAGES = ["caption", "scaling", "fullsbs", "interpolate", "singleloop", "dubbing/sfx", "slides", "slideshow", "watermark/encrypt", "watermark/decrypt", "concat", "check/rate", "check/released"]
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
uml_def = os.path.join(uml_folder, "autoforward.pu")
with open(uml_def, "w") as f:
    f.write("' This file is generated and contains PlantUML commands - do not edit.\n")
    f.write("\n")
    f.write("@startuml\n")
    f.write("scale max 3840*2160\n")
    f.write("<style>\n")
    f.write("document {\n")
    f.write("  BackGroundColor darkgray\n")
    f.write("}\n")
    f.write("root {\n")
    f.write("  FontColor #?black:white\n")
    f.write("  LineColor white\n")
    f.write("}\n")
    f.write("</style>\n")
    f.write("' Indicate the direction of the flowchart\n")
    f.write("left to right direction\n")
    f.write("title\n")
    f.write("<i>VR We Are</i> Pipeline\n")
    f.write("end title\n")
    f.write("note as N1\n")
    f.write("  You can drop files\n")
    f.write("  at any stage.\n")
    f.write("endnote\n")
    f.write("\n")
    

    # scan stage forward rules to find state starts and ends
    targets=[]
    involved=[]
    startsCand=[]
    transitionRules=[]
    typeDef=[]
    childs=[]
    nocleanup=[]
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
        try:
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
        except Exception as e:
            typeDef.append(" : error (json)")
            if not s in involved:
                involved.append(s)

        nocleanupfile = os.path.join(path, "../../../../input/vr/" + stage + "/done/.nocleanup")
        if os.path.exists(nocleanupfile):
            childs.append(" {\n  state keep"+str(s)+" <<history>>\n}")
            nocleanup.append(True)
            if not s in involved:
                involved.append(s)            
            if not s in startsCand:
                startsCand.append(s)            
        else:
            childs.append("")
            nocleanup.append(False)
        
    for s in range(len(STAGES)):
        stage=STAGES[s]

        forwarddef = os.path.join(path, "../../../../output/vr/" + stage + "/forward.txt")
        if os.path.exists(forwarddef):
            startsCand.append(s)
            if not s in involved:
                involved.append(s)
            with open(forwarddef) as file:
                usedRuleCount=0
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
                    try:
                        usedRuleCount+=1
                        sidx=STAGES.index(stage)
                        if not sidx in involved:
                            involved.append(sidx)
                        targets.append(sidx)
                        style=""
                        style2=""
                        if usedRuleCount==1:
                            style="bold"
                            style2=style+","
                        targetType=typeDef[sidx]
                        if targetType == " : video":
                            style="["+style2+"#04018C]"
                        elif targetType == " : image":
                            style="["+style2+"#018C08]"
                        elif not targetType == "":
                            style="["+style2+"#8C018C]"
                        elif not style  == "":
                            style="["+style+"]"
                            
                        name = "stage" #"nocleanup" if nocleanup[sidx] else "stage"
                        transitionRules.append("stage" + str(s) + " -"+style+"-> " + name + str(sidx) + options)
                    except Exception as e:
                        typeDef[s]=" : error (forward)"

    f.write("' Aliases\n")
    #for s in involved:
    for s in involved:
        stage=STAGES[s]
        style=" ##"
        type=typeDef[s]
        
        if re.match(r"tasks/_", stage):
            style=style+"[dotted]"
        elif not re.match(r"tasks/", stage):
            style=style+"[bold]"
            
        if type == " : error":
            style=style+"FF0000"
        elif type == " : video":
            style=style+"04018C"
        elif type == " : image":
            style=style+"018C08"
        elif not type == "":
            style=style+"8C018C"
        else:
            style=style+"000000"
            
            #  + style  typeDef[s]
        f.write("state \"" + stage + "\" as stage" + str(s) + style + childs[s]  + "\n")
        
    f.write("\n")

     
    f.write("' Starts\n")
    for s in startsCand:
        stage=STAGES[s]
        if not s in targets:
            style=""
            type=typeDef[s]
            if type == " : video":
                style="[#04018C]"
            elif type == " : image":
                style="[#018C08]"
            elif not type == " : ":
                style="[#8C018C]"
            else:
                style="[#darkgray]"
            name = "stage" #"nocleanup" if nocleanup[s] else "stage"
            f.write("[*] -" + style + "-> " + name + str(s) + "\n")
    f.write("\n")

    f.write("' Transitions\n")
    for t in transitionRules:
        f.write(t + "\n")
    f.write("\n")
 
    f.write("' True Ends without forward.txt\n")
    for s in involved:
        stage=STAGES[s]
        if not s in startsCand:
            style="[#000000]"
            f.write("stage" + str(s) + " -" + style + "-> [*]\n")
    f.write("\n")

    f.write("@enduml\n")

