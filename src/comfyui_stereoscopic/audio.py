import os

import numpy as np
import soundfile as sf

import folder_paths

class SaveAudioSimple:

    OUTPUT_NODE = True

    @classmethod
    def INPUT_TYPES(s):
        return {"required": { "audio": ("AUDIO", ),
                              "filename_prefix": ("STRING", {"default": "audio/sound"}),
                              "format": (["flac"], {"default": "flac"}),
                            },
                }
    RETURN_TYPES = ()
    
    FUNCTION = "save"
    CATEGORY = "Stereoscopic"
    DESCRIPTION = "Save audio to file, overwrite any exiting."
    
    def save(self, audio, filename_prefix="audio/sound", format="flac"):

        sample_rate = audio["sample_rate"]
        waveform = audio["waveform"].cpu()
        file = f"{filename_prefix}.{format}"
        path = os.path.realpath( os.path.join( os.path.realpath( folder_paths.get_output_directory() ), file )  )
        dir = os.path.dirname( path )
        os.makedirs(dir, exist_ok=True)
        
        # Schritt 1: batch-Dimension wegnehmen → (channels, samples)
        x = waveform.squeeze(0)   # jetzt (1, 38912)

        # Schritt 2: transponieren → (samples, channels)
        x = x.transpose(0, 1)   # jetzt (38912, 1)

        # Schritt 3: als NumPy speichern
        sf.write(path, x.numpy(), sample_rate)

        result = []
        result.append( () )
        
        return ( result )
