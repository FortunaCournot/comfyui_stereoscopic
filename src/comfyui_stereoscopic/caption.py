
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
    DESCRIPTION = "Strip XML from text."
    
    def execute(self, formatted):
        return ( stripXML(formatted) )
  