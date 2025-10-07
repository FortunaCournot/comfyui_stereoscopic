import os
import folder_paths
import time


config_files_path = os.path.abspath(os.path.join(folder_paths.get_user_directory(), 'default', 'comfyui_stereoscopic'))

def touch(fname):
    if os.path.exists(fname):
        os.utime(fname, None)
    else:
        open(fname, 'a').close()
        
'''
To be used at start of pipeline, to ensure there is no concurrent process.
'''
class VRwearePause:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "anything": (("*",), {"forceInput": True}),
            }
        }

    RETURN_TYPES = ("*",)
    RETURN_NAMES = ("anything",)
    FUNCTION = "execute"
    CATEGORY = "Stereoscopic"
    DESCRIPTION = "Pause pipeline, to be used at start of workflow, to ensure there is no concurrent pipeline process. It waits until the pipeline is paused. forwarding is not affected."
    
    def execute(self, anything):
        touch( os.path.abspath(os.path.join(config_files_path, '.pipelinepause')) )
        pipelineActiveLockPath = os.path.abspath(os.path.join(config_files_path, '.pipelineactive'))
        if os.path.exists(pipelineActiveLockPath):
            print(f"[comfyui_stereoscopic] VR we are pipeline pause requested. Stopping...")
            while os.path.exists(pipelineActiveLockPath):
                time.sleep(1)
        print(f"[comfyui_stereoscopic] paused.")
        return (anything,)


class VRweareResume:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "anything": (("*",), {"forceInput": True}),
            }
        }

    RETURN_TYPES = ("*",)
    RETURN_NAMES = ("anything",)
    FUNCTION = "execute"
    CATEGORY = "Stereoscopic"
    DESCRIPTION = "Resume pipeline. To be used as  the queue."
    
    def execute(self, anything):
        pause_file_path = os.path.abspath(os.path.join(config_files_path, '.pipelinepause'))
        if os.path.exists(pause_file_path): os.remove(pause_file_path)
        return (anything,)


