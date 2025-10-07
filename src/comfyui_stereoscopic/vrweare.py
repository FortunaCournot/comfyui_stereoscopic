
class VRwearePause:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
            }
        }

    RETURN_TYPES = ()
    RETURN_NAMES = ()
    FUNCTION = "execute"
    CATEGORY = "Stereoscopic"
    DESCRIPTION = "Pause pipeline"
    
    def execute(self):
        pass

class VRweareResume:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
            }
        }

    RETURN_TYPES = ()
    RETURN_NAMES = ()
    FUNCTION = "execute"
    CATEGORY = "Stereoscopic"
    DESCRIPTION = "Resume pipeline"
    
    def execute(self):
        pass


