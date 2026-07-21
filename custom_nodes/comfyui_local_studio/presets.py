from pathlib import PurePosixPath


RESOLUTION_PRESETS = {
    "Square 1:1": (1024, 1024),
    "Portrait 4:5": (896, 1152),
    "Photo Portrait 2:3": (832, 1216),
    "Tall 9:16": (768, 1344),
    "Landscape 5:4": (1152, 896),
    "Photo Landscape 3:2": (1216, 832),
    "Wide 16:9": (1344, 768),
}

STYLE_PRESETS = {
    "photo": {
        "None": ("", ""),
        "Natural": ("natural documentary photography, realistic texture, available light", "plastic skin"),
        "Studio Portrait": ("professional studio portrait, controlled softbox lighting, detailed skin", "flat lighting"),
        "Cinematic": ("cinematic photography, motivated lighting, filmic color grading", "flat composition"),
        "Editorial": ("editorial photography, deliberate styling, polished composition", "snapshot"),
        "Product/Macro": ("commercial product photography, macro detail, clean controlled lighting", "cluttered background"),
        "Landscape/Travel": ("travel photography, atmospheric depth, natural color, detailed landscape", "hazy subject"),
        "Vintage Film": ("vintage analog film photograph, subtle grain, restrained color palette", "digital oversharpening"),
    },
    "anime": {
        "None": ("", ""),
        "Clean Cel": ("clean cel shading, precise line art, controlled color palette", "messy line art"),
        "Painterly": ("painterly anime illustration, textured brushwork, expressive light", "flat color"),
        "Manga Ink": ("manga ink drawing, confident line weight, screentone shading", "colored rendering"),
        "Soft Shoujo": ("soft shoujo illustration, delicate lines, luminous pastel color", "harsh shadows"),
        "Dynamic Action": ("dynamic anime action composition, strong foreshortening, speed lines", "static pose"),
        "Fantasy": ("fantasy anime illustration, ornate detail, magical atmosphere", "modern mundane setting"),
        "Retro 90s": ("1990s anime cel aesthetic, hand-painted background, period color palette", "modern 3d render"),
    },
    "general": {
        "None": ("", ""),
        "Natural": ("natural photographic rendering, realistic texture and light", "plastic texture"),
        "Cinematic": ("cinematic composition, filmic light and color", "flat composition"),
        "Editorial": ("polished editorial composition and deliberate styling", "snapshot"),
        "Illustration": ("detailed illustrative rendering, cohesive palette", "unfinished sketch"),
        "Vintage Film": ("vintage analog film character, subtle grain", "digital oversharpening"),
    },
}

LORA_PREFIXES = {
    "sdxl": "sdxl/",
    "z-image": "z-image/",
    "flux2": "flux2/",
}

LORA_LABELS = {
    "sdxl": "SDXL",
    "z-image": "Z-Image",
    "flux2": "FLUX.2",
}

CONTROL_PRESETS = {
    "Canny": (1, "canny/lineart/anime_lineart/mlsd"),
    "Depth": (2, "depth"),
    "Pose": (3, "openpose"),
}


def get_resolution(name: str) -> tuple[int, int]:
    try:
        return RESOLUTION_PRESETS[name]
    except KeyError as error:
        raise ValueError(f"Unknown resolution preset: {name}") from error


def compose_style(family: str, style: str, positive: str, negative: str) -> tuple[str, str]:
    try:
        positive_suffix, negative_suffix = STYLE_PRESETS[family][style]
    except KeyError as error:
        raise ValueError(f"Style {style!r} is not valid for family {family!r}") from error
    return _append(positive, positive_suffix), _append(negative, negative_suffix)


def validate_lora_path(family: str, path: str | None) -> str | None:
    if path is None or path.strip().lower() in {"", "none"}:
        return None
    if family not in LORA_PREFIXES:
        raise ValueError(f"Unknown LoRA family: {family}")

    normalized = path.replace("\\", "/").strip()
    parts = PurePosixPath(normalized).parts
    if PurePosixPath(normalized).is_absolute() or ".." in parts:
        raise ValueError("LoRA path must remain inside the configured family directory")
    if not normalized.lower().startswith(LORA_PREFIXES[family]):
        raise ValueError(f"Expected a {LORA_LABELS[family]} LoRA under {LORA_PREFIXES[family]}")
    return normalized


def get_control_preset(mode: str) -> tuple[int, str]:
    try:
        return CONTROL_PRESETS[mode]
    except KeyError as error:
        raise ValueError(f"Unknown control mode: {mode}") from error


def _append(base: str, suffix: str) -> str:
    clean_base = base.strip().rstrip(",")
    clean_suffix = suffix.strip().strip(",")
    return ", ".join(part for part in (clean_base, clean_suffix) if part)
