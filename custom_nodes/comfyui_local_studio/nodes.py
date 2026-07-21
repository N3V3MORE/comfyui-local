import comfy.sd
import comfy.utils
import folder_paths

from .presets import (
    CONTROL_PRESETS,
    LORA_PREFIXES,
    RESOLUTION_PRESETS,
    STYLE_PRESETS,
    compose_style,
    get_control_preset,
    get_resolution,
    validate_lora_path,
)


class StudioResolutionPreset:
    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {"preset": (list(RESOLUTION_PRESETS),)}}

    RETURN_TYPES = ("INT", "INT", "STRING")
    RETURN_NAMES = ("width", "height", "label")
    FUNCTION = "resolve"
    CATEGORY = "ComfyUI Local Studio"

    def resolve(self, preset):
        width, height = get_resolution(preset)
        return width, height, preset


class _StudioStylePrompt:
    FAMILY = "general"

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "positive": ("STRING", {"multiline": True, "default": ""}),
                "negative": ("STRING", {"multiline": True, "default": ""}),
                "style": (list(STYLE_PRESETS[cls.FAMILY]),),
            }
        }

    RETURN_TYPES = ("STRING", "STRING")
    RETURN_NAMES = ("positive", "negative")
    FUNCTION = "apply"
    CATEGORY = "ComfyUI Local Studio"

    def apply(self, positive, negative, style):
        return compose_style(self.FAMILY, style, positive, negative)


class StudioPhotoStylePrompt(_StudioStylePrompt):
    FAMILY = "photo"


class StudioAnimeStylePrompt(_StudioStylePrompt):
    FAMILY = "anime"


class StudioGeneralStylePrompt(_StudioStylePrompt):
    FAMILY = "general"


class StudioControlPreset:
    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {"mode": (list(CONTROL_PRESETS),)}}

    RETURN_TYPES = ("INT", "STRING")
    RETURN_NAMES = ("switch", "union_type")
    FUNCTION = "resolve"
    CATEGORY = "ComfyUI Local Studio"

    def resolve(self, mode):
        return get_control_preset(mode)


def _lora_names(family):
    prefix = LORA_PREFIXES[family]
    names = [name for name in folder_paths.get_filename_list("loras") if name.replace("\\", "/").lower().startswith(prefix)]
    return ["None", *sorted(names, key=str.lower)]


def _load_lora(model, clip, family, lora_name, strength_model, strength_clip):
    validated = validate_lora_path(family, lora_name)
    if validated is None:
        return model, clip
    path = folder_paths.get_full_path_or_raise("loras", validated)
    weights = comfy.utils.load_torch_file(path, safe_load=True)
    return comfy.sd.load_lora_for_models(model, clip, weights, strength_model, strength_clip)


class StudioSDXLLoraLoader:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "model": ("MODEL",),
                "clip": ("CLIP",),
                "lora_name": (_lora_names("sdxl"),),
                "strength_model": ("FLOAT", {"default": 0.8, "min": -2.0, "max": 2.0, "step": 0.05}),
                "strength_clip": ("FLOAT", {"default": 0.8, "min": -2.0, "max": 2.0, "step": 0.05}),
            }
        }

    RETURN_TYPES = ("MODEL", "CLIP")
    FUNCTION = "load"
    CATEGORY = "ComfyUI Local Studio"

    def load(self, model, clip, lora_name, strength_model, strength_clip):
        return _load_lora(model, clip, "sdxl", lora_name, strength_model, strength_clip)


class _StudioModelLoraLoader:
    FAMILY = "z-image"

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "model": ("MODEL",),
                "lora_name": (_lora_names(cls.FAMILY),),
                "strength_model": ("FLOAT", {"default": 0.8, "min": -2.0, "max": 2.0, "step": 0.05}),
            }
        }

    RETURN_TYPES = ("MODEL",)
    FUNCTION = "load"
    CATEGORY = "ComfyUI Local Studio"

    def load(self, model, lora_name, strength_model):
        loaded_model, _ = _load_lora(model, None, self.FAMILY, lora_name, strength_model, 0.0)
        return (loaded_model,)


class StudioZImageLoraLoader(_StudioModelLoraLoader):
    FAMILY = "z-image"


class StudioFlux2LoraLoader(_StudioModelLoraLoader):
    FAMILY = "flux2"


NODE_CLASS_MAPPINGS = {
    "StudioResolutionPreset": StudioResolutionPreset,
    "StudioPhotoStylePrompt": StudioPhotoStylePrompt,
    "StudioAnimeStylePrompt": StudioAnimeStylePrompt,
    "StudioGeneralStylePrompt": StudioGeneralStylePrompt,
    "StudioControlPreset": StudioControlPreset,
    "StudioSDXLLoraLoader": StudioSDXLLoraLoader,
    "StudioZImageLoraLoader": StudioZImageLoraLoader,
    "StudioFlux2LoraLoader": StudioFlux2LoraLoader,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "StudioResolutionPreset": "Studio Resolution Preset",
    "StudioPhotoStylePrompt": "Studio Photo Style",
    "StudioAnimeStylePrompt": "Studio Anime Style",
    "StudioGeneralStylePrompt": "Studio General Style",
    "StudioControlPreset": "Studio Control Preset",
    "StudioSDXLLoraLoader": "Studio Optional SDXL LoRA",
    "StudioZImageLoraLoader": "Studio Optional Z-Image LoRA",
    "StudioFlux2LoraLoader": "Studio Optional FLUX.2 LoRA",
}
