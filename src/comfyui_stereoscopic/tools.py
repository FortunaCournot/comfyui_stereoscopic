import numpy as np
import torch
import io
import os
import re
import sys
import yaml
import math
import random
import time
from typing import Dict, Any, List
import json
import uuid

import folder_paths
    
class GetResolutionForVR:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "base_image": ("IMAGE",),
            }
        }

    RETURN_TYPES = ("INT", "INT", "INT", "INT",)
    RETURN_NAMES = ("width", "height", "count", "resolution",)
    FUNCTION = "execute"
    CATEGORY = "Stereoscopic"
    DESCRIPTION = "Get resolution for depth image from base image."
    
    def execute(self, base_image):
        w = int(base_image.shape[2])
        h = int(base_image.shape[1])
        c = int(base_image.shape[0])
        r = int(min(w, h))
        print(f"GetResolutionForVR: w={w}, h={h}, c={c}, r={r}", flush=True)
        return (w, h, c, r)

class LinearFade:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "images": ("IMAGE",),
                "start": ("FLOAT", {"default": 1.0, "min": 0.0, "max": 1.0}),
                "mid": ("FLOAT", {"default": 0.0, "min": 0.0, "max": 1.0}),
                "end": ("FLOAT", {"default": 0.0, "min": 0.0, "max": 1.0}),
                "midpoint": ("FLOAT", {"default": 0.2, "min": 0.0, "max": 1.0}),
            },
        }

    RETURN_TYPES = ("IMAGE", "FLOAT")
    RETURN_NAMES = ("image", "strength")
    FUNCTION = "fade"
    CATEGORY = "Stereoscopic"


    def fade(self, images, start, mid, end, midpoint):
        num_images = len(images)
        if num_images == 0:
            return ([], [])

        # mid gibt an, wo zwischen 0 und 1 der Übergang liegt
        # → entspricht also einem prozentualen Anteil der Bildliste
        mid_index = int(num_images * midpoint)
        mid_index = max(1, min(mid_index, num_images - 1))  # Grenzen absichern

        strengths = []
        for i in range(num_images):
            if i < mid_index:
                # Interpolieren zwischen start → midpoint
                t = i / max(1, mid_index - 1)
                strength = start + t * (mid - start)
            else:
                # Interpolieren zwischen midpoint → end
                t = (i - mid_index) / max(1, num_images - mid_index - 1)
                strength = mid + t * (end - mid)
            strengths.append(strength)

        # ⚠️ WICHTIG: separat zurückgeben (nicht als Tupel!)
        return (images, strengths)


class ColorCorrectBatch:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "images": ("IMAGE",),  # Tensor mit Shape [B, H, W, C]
                "saturation": ("FLOAT", {"forceInput": True}),  # Liste von Floats
            },
        }

    RETURN_TYPES = ("IMAGE",)
    RETURN_NAMES = ("corrected_images",)
    FUNCTION = "apply"
    CATEGORY = "Stereoscopic"
    DESCRIPTION = (
        "Wendet eine Sättigungskorrektur auf ein Batch von Bildern an. "
        "Der Input 'images' ist ein Tensor [B, H, W, C]; 'saturation' ist eine Liste von Float-Werten "
        "mit der gleichen Länge wie die Batchgröße."
    )

    def apply(self, images, saturation):
        # Sicherstellen, dass saturation eine Liste ist
        if not isinstance(saturation, (list, tuple)):
            saturation = [saturation]

        batch_size = images.shape[0]
        if len(saturation) != batch_size:
            raise ValueError(
                f"Länge der Sättigungsliste ({len(saturation)}) muss der Batchgröße ({batch_size}) entsprechen."
            )

        # Wir kopieren, um nicht das Original zu verändern
        corrected = []
        weights = torch.tensor([0.299, 0.587, 0.114], device=images.device, dtype=images.dtype)

        for i in range(batch_size):
            img = images[i]  # [H, W, C]
            sat = float(saturation[i])
            gray = torch.sum(img * weights, dim=-1, keepdim=True)  # Luminanzkanal
            adjusted = gray + (img - gray) * sat
            adjusted = torch.clamp(adjusted, 0.0, 1.0)
            corrected.append(adjusted)

        corrected_tensor = torch.stack(corrected, dim=0)  # [B, H, W, C]
        return (corrected_tensor,)
        



class VariantPromptBuilder:
    """Builds a prompt using extended placeholders from a properties dict."""

    CATEGORY = "Stereoscopic"
    RETURN_TYPES = ("STRING",)
    RETURN_NAMES = ("final_prompt",)
    FUNCTION = "build_prompt"

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "prompt_template": ("STRING", {
                    "multiline": True,
                    "default": "A {if haircolor}{haircolor} human{/if} with {iris|unknown} eyes."
                }),
                "properties": ("DICT",),
            }
        }

    def build_prompt(self, prompt_template: str, properties: dict) -> tuple[str]:
        """Replaces placeholders in prompt_template using properties dict."""

        if not isinstance(properties, dict):
            properties = {}

        text = prompt_template

        # --- Escape literal braces temporarily ---
        text = text.replace("{{", "__LEFT_BRACE__").replace("}}", "__RIGHT_BRACE__")

        # --- Process {if key}...{/if} blocks ---
        def process_if(match):
            key = match.group(1)
            block = match.group(2)
            return block if properties.get(key) else ""

        text = re.sub(r"\{if (\w+)\}(.*?)\{/if\}", process_if, text, flags=re.DOTALL)

        # --- Process {ifnot key}...{/ifnot} blocks ---
        def process_ifnot(match):
            key = match.group(1)
            block = match.group(2)
            return block if not properties.get(key) else ""

        text = re.sub(r"\{ifnot (\w+)\}(.*?)\{/ifnot\}", process_ifnot, text, flags=re.DOTALL)

        # --- Process {key|default} and {key} ---
        def replace_key(match):
            expr = match.group(1)
            if "|" in expr:
                key, default = expr.split("|", 1)
            else:
                key, default = expr, ""
            return str(properties.get(key, default))

        text = re.sub(r"\{(\w+(?:\|[^}]+)?)\}", replace_key, text)

        # --- Restore literal braces ---
        text = text.replace("__LEFT_BRACE__", "{").replace("__RIGHT_BRACE__", "}")

        return (text,)



class JoinVariantProperties:
    """
    Custom ComfyUI node that merges two DICT inputs from GetVariant nodes.
    properties2 overrides properties1 on key collisions.
    """

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "properties1": ("DICT", {}),
                "properties2": ("DICT", {}),
            }
        }
        
    RETURN_TYPES = ("DICT",)
    RETURN_NAMES = ("properties",)
    FUNCTION = "join"
    CATEGORY = "Stereoscopic"

    def join(self, properties1: Dict[str, Any], properties2: Dict[str, Any]):
        # Defensive copy
        merged = {}
        if isinstance(properties1, dict):
            merged.update(properties1)
        if isinstance(properties2, dict):
            merged.update(properties2)
        return (merged,)



class SpecVariants:
    """
    Builds a VariantSelectionPath list representing the hierarchical path
    through a YAML profile of this structure:

    profile:
      name: human
      variations:
      - variant:
          weight: 1.0
          props:
            ...
          variations:
          - variant:
              weight: ...
              props:
                ...
              variations: ...

    The node either reads VariantIndexValues (comma-separated string)
    or generates a random path based on weights.
    """

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "yaml_path": ("STRING", {
                    "multiline": False,
                    "default": "",
                }),
            },
            "optional": {
                "VariantIndexValues": ("STRING", {
                    "multiline": False,
                    "default": "",
                    "placeholder": "e.g. 0,1,2"
                }),
                "random_seed": ("INT", {
                    "default": 0,
                    "min": 0,
                    "max": 2**31 - 1,
                    "step": 1
                }),
                "seed_offset": ("INT", {
                    "default": random.randint(0, 2**31 - 1),
                    "min": 0,
                    "max": 2**31 - 1,
                    "step": 1
                }),
            }
        }

    RETURN_TYPES = ("DICT", "FLOAT", "INT",)
    RETURN_NAMES = ("properties", "probability", "used_seed",)
    CATEGORY = "Stereoscopic"
    FUNCTION = "execute"

    # ------------------------------------------------------------------

    def execute(self, yaml_path: str, VariantIndexValues: str = "", random_seed: int = 0, seed_offset: int = 0):
        """Generates or validates a VariantSelectionPath for a hierarchical YAML profile."""

        # --- RNG setup ---
        if isinstance(random_seed, int) and random_seed > 0:
            used_seed = random_seed
        else:
            used_seed = int(time.time() * 1000) % (2**31 - 1)

        # create persistent node-specific id if not already present
        if not hasattr(self, "instance_id"):
            self.instance_id = str(uuid.uuid4())

        used_seed = random_seed + seed_offset
        
        rng = random.Random(used_seed)

        yaml_path = os.path.realpath( os.path.join( os.path.realpath( folder_paths.get_input_directory() ), yaml_path ) )

        # --- Load YAML ---
        if not yaml_path or not os.path.exists(yaml_path):
            raise FileNotFoundError(f"YAML file not found: {yaml_path}")

        with open(yaml_path, "r", encoding="utf-8") as f:
            yaml_data = yaml.safe_load(f) or {}

        profile = yaml_data.get("profile", {})
        if not profile:
            raise ValueError("YAML file does not contain a valid 'profile' element.")

        variations = profile.get("variations", [])
        if not isinstance(variations, list) or not variations:
            raise ValueError("YAML 'variations' must be a non-empty list.")

        # --- Parse VariantIndexValues ---
        if VariantIndexValues.strip():
            try:
                VariantSelectionPath = [int(x.strip()) for x in VariantIndexValues.split(",") if x.strip() != ""]
            except ValueError:
                raise ValueError(f"Invalid VariantIndexValues format: {VariantIndexValues}")
        else:
            VariantSelectionPath = []

        # --- Generate or Validate Path ---
        if len(VariantSelectionPath) == 0:
            VariantSelectionPath = self._generate_random_path(variations, rng)
        else:
            self._validate_path(variations, VariantSelectionPath)

        # --- Traverse hierarchy ---
        result = {}
        probability = self._traverse_path(variations, VariantSelectionPath, result, level=0)

        return (result, probability, used_seed)

    # ------------------------------------------------------------------

    def _generate_random_path(self, variations, rng):
        """Recursively builds a random path through the hierarchy, weighted by `variant.weight`."""
        path = []
        current_variations = variations

        while isinstance(current_variations, list) and len(current_variations) > 0:
            weights = []
            for item in current_variations:
                variant = item.get("variant", {})
                w = float(variant.get("weight", 1.0))  # ✅ weight is inside `variant`
                weights.append(w)

            idx = rng.choices(range(len(current_variations)), weights=weights, k=1)[0]
            path.append(idx)

            next_variant = current_variations[idx].get("variant", {})
            current_variations = next_variant.get("variations", [])

        return path

    # ------------------------------------------------------------------

    def _validate_path(self, variations, path):
        """Ensure the VariantSelectionPath is valid for the actual YAML hierarchy."""
        current_variations = variations
        for depth, idx in enumerate(path):
            if not isinstance(idx, int):
                raise ValueError(f"Variant index at depth {depth} must be integer, got {idx}")
            if not (0 <= idx < len(current_variations)):
                raise ValueError(
                    f"Invalid index {idx} at depth {depth}: "
                    f"there are only {len(current_variations)} variants at this level."
                )

            current_variant = current_variations[idx].get("variant", {})
            current_variations = current_variant.get("variations", [])
            
    # ------------------------------------------------------------

    def _traverse_path(self, variations, path, result, level):
        """
        Recursively traverses the variant tree along VariantSelectionPath.
        Returns the cumulative probability of the selected path.
        """
        if not variations or level >= len(path):
            return 1.0  # neutral multiplicative identity

        index = path[level]
        if not (0 <= index < len(variations)):
            raise ValueError(f"Invalid index {index} at level {level} (max {len(variations) - 1})")

        # Get current variant
        current = variations[index].get("variant", {})
        if not isinstance(current, dict):
            raise ValueError(f"Invalid variant structure at level {level}")

        # Extract properties
        props = current.get("props", {})
        if not isinstance(props, dict):
            raise ValueError(f"Missing or invalid 'props' dict at level {level}")

        for k, v in props.items():
            if k not in result:
                result[k] = v

        # Compute normalized probability contribution for this level
        total_weight = 0.0
        for v in variations:
            variant = v.get("variant", {})
            total_weight += float(variant.get("weight", 1.0))

        current_weight = float(current.get("weight", 1.0))
        local_probability = current_weight / total_weight if total_weight > 0 else 0.0

        # Recurse into next level
        next_variations = current.get("variations", [])
        sub_probability = 1.0
        if isinstance(next_variations, list) and len(next_variations) > 0:
            sub_probability = self._traverse_path(next_variations, path, result, level + 1)

        # Multiply local probability by the subpath probability
        return local_probability * sub_probability
        
        
        
class GradeVariant:
    """
    Get a random variant from a gradable text, containing a property with the given key and a random text value. Texts should be based on gradable adjectives that describe a quality on a spectrum, or adverbs of degree, assigned with a value or probability threshold. Selections are made according to the relative weights.
    """

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "key": ("STRING", {}),          # key for entry
                "random_seed": ("INT", {
                    "default": 0,
                    "min": 0,
                    "max": 2**31 - 1,
                    "step": 1
                }),
                "seed_offset": ("INT", {
                    "default": random.randint(0, 2**31 - 1),
                    "min": 0,
                    "max": 2**31 - 1,
                    "step": 1
                }),
                # Widgets receive JSON strings (handled by JS)
                "weights": ("STRING", {"default": "[]"}),
                "texts": ("STRING", {"default": "[]"}),
            }
        }

    RETURN_TYPES = ("DICT", "FLOAT", "INT",)
    RETURN_NAMES = ("properties", "probability", "used_seed",)
    FUNCTION = "execute"
    CATEGORY = "Stereoscopic"
    
    def execute(self, key, random_seed, seed_offset, weights, texts):
        import json

        try:
            weights = json.loads(weights)
        except Exception:
            weights = []

        try:
            texts = json.loads(texts)
        except Exception:
            texts = []

        # safety
        if len(weights) != len(texts):
            raise ValueError("Weights and texts must have same length.")

        # ---
        
        # create persistent node-specific id if not already present
        if not hasattr(self, "instance_id"):
            self.instance_id = str(uuid.uuid4())
            
        if isinstance(random_seed, int) and random_seed > 0:
            used_seed = random_seed
        else:
            used_seed = int(time.time() * 1000) % (2**31 - 1)

        used_seed = random_seed + seed_offset

        rng = random.Random(used_seed)
            
        # ---

        idx = rng.choices(range(len(texts)), weights=weights, k=1)[0]

        # Compute normalized probability contribution for this level
        total_weight = 0.0
        for w in weights:
            total_weight += w

        current_weight = weights[idx] if idx is not None else 0.0
        probability = current_weight / total_weight if total_weight > 0 else 0.0
        value = texts[idx] if idx is not None else ""
        
        return ({key: value}, probability, used_seed,)


