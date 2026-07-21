from __future__ import annotations

from pathlib import Path
from typing import Any

from .compiler import compile_api_prompt
from .manifests import load_models, load_workflow_specs


class BenchmarkError(ValueError):
    pass


def materialize_prompt(
    root: Path,
    *,
    model_id: str,
    width: int,
    height: int,
    seed: int,
    filename_prefix: str,
    positive_prompt: str | None = None,
    negative_prompt: str | None = None,
) -> dict[str, Any]:
    if width <= 0 or height <= 0 or width % 64 or height % 64:
        raise BenchmarkError("Prompt dimensions must be positive multiples of 64")

    models = load_models(root)
    model = models.get(model_id)
    if model is None:
        raise BenchmarkError(f"Unknown model: {model_id}")

    specs = [spec for spec in load_workflow_specs(root) if spec.model_profile == model_id and spec.group == "Create"]
    if len(specs) != 1:
        raise BenchmarkError(f"Model {model_id} has {len(specs)} Create workflow specifications; expected one")
    defaults = specs[0].defaults

    return compile_api_prompt(
        root,
        model,
        positive_prompt=positive_prompt if positive_prompt is not None else defaults["positivePrompt"],
        negative_prompt=negative_prompt if negative_prompt is not None else defaults.get("negativePrompt", ""),
        width=width,
        height=height,
        seed=seed,
        filename_prefix=filename_prefix,
    )
