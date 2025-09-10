from plantuml import PlantUML
import os

try:
    path = os.path.dirname(os.path.abspath(__file__))
    uml_folder = os.path.join(path, "../../../../user/default/comfyui_stereoscopic/uml")
    uml_def = os.path.join(uml_folder, "autoforward.pu")

    # generate UML image
    server = PlantUML(url='http://www.plantuml.com/plantuml/img/',
                          basic_auth={},
                          form_auth={}, http_opts={}, request_opts={})

    # Call the PlantUML server on the .txt file
    server.processes_file(uml_def)
        
except Exception as e:
    print('Info: failed to create pipeline UML image. ', e)
    
