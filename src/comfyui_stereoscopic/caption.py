import io
import os

import folder_paths


def stripXML(inStr):
  a = inStr.find('<')
  b = inStr.find('>')
  if a < 0 and b < 0:
    return inStr
  elif b < 0:
    return inStr[:a] + stripXML(inStr[a+1:])
  elif a < 0:
    return inStr[:b] + stripXML(inStr[b+1:])
  elif a > b:
    return inStr[:b] + stripXML(inStr[b+1:])
  return inStr[:a] + stripXML(inStr[b+1:])


class StripXML:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "formatted": ("STRING", {"default": ""})
            }
        }

    RETURN_TYPES = ("STRING",)
    RETURN_NAMES = ("raw",)
    FUNCTION = "execute"
    CATEGORY = "Stereoscopic"
    DESCRIPTION = "Strip off XML from text."
    
    def execute(self, formatted):
    
        result1 = stripXML(formatted)
        
        result = []
        result.append(result1)
        
        return ( result )


class SaveStrippedUTF8File:
    OUTPUT_NODE = True

    @classmethod
    def INPUT_TYPES(s):
        return {
            "required": {
                "file": ("STRING", {"default": "file.txt"}),
                "raw": ("STRING", {"forceInput": True, "multiline": True}),
            },
        }

    RETURN_TYPES = ("STRING",)
    RETURN_NAMES = ("raw",)
    FUNCTION = "execute"
    CATEGORY = "Stereoscopic"
    DESCRIPTION = "Strip off XML from text and save it to file."

    def execute(self, file, raw):

        stripped = str(stripXML(raw))

        path = os.path.realpath( os.path.join( os.path.realpath( folder_paths.get_output_directory() ), file ) )

        with open(path, "w", encoding="utf-8") as f:
            f.write(stripped)
 
        result = []
        result.append(stripped)
        
        return ( result )
