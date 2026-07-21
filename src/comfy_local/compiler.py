from __future__ import annotations

import json
from copy import deepcopy
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .api_prompt import ApiPromptGraph
from .builder import GraphBuilder
from .graph import WorkflowGraph
from .manifests import ModelProfile, WorkflowSpec, load_models, load_workflow_specs, validate_configuration
from .templates import load_template
from .validation import validate_ui_graph


class CompilerError(ValueError):
    pass


@dataclass(frozen=True)
class CompiledWorkflow:
    spec: WorkflowSpec
    app: dict[str, Any]
    ui: dict[str, Any] | None
    api_prompt: dict[str, Any] | None


@dataclass(frozen=True)
class CompileResult:
    apps: tuple[str, ...]
    ui_workflows: tuple[str, ...]
    api_prompts: tuple[str, ...]

    @property
    def relative_files(self) -> tuple[str, ...]:
        return tuple(sorted(self.apps + self.ui_workflows + self.api_prompts))


UI_OUTPUTS = {
    "realvis-xl": "realistic-sdxl.json",
    "animagine-xl": "anime-sdxl.json",
    "z-image-turbo": "z-image-turbo.json",
    "flux2-klein": "flux2-klein.json",
}

API_OUTPUTS = {
    "realvis-xl": "sdxl.json",
    "z-image-turbo": "z_image.json",
    "flux2-klein": "flux2.json",
}


def compile_catalog(root: Path, output_root: Path) -> CompileResult:
    validate_configuration(root)
    models = load_models(root)
    specs = load_workflow_specs(root)
    apps: list[str] = []
    ui_workflows: list[str] = []
    api_prompts: list[str] = []

    for spec in specs:
        compiled = compile_spec(root, spec, models)
        app_relative = (Path("workflows") / "apps" / Path(spec.output)).as_posix()
        _write_json(output_root / app_relative, compiled.app)
        apps.append(app_relative)

        if compiled.ui is not None and spec.id in UI_OUTPUTS:
            ui_relative = (Path("workflows") / "ui" / UI_OUTPUTS[spec.id]).as_posix()
            _write_json(output_root / ui_relative, compiled.ui)
            ui_workflows.append(ui_relative)

        if compiled.api_prompt is not None and spec.id in API_OUTPUTS:
            api_relative = (Path("workflows") / "api" / API_OUTPUTS[spec.id]).as_posix()
            _write_json(output_root / api_relative, compiled.api_prompt)
            api_prompts.append(api_relative)

    return CompileResult(tuple(apps), tuple(ui_workflows), tuple(api_prompts))


def compile_spec(root: Path, spec: WorkflowSpec, models: dict[str, ModelProfile]) -> CompiledWorkflow:
    model = models.get(spec.model_profile) if spec.model_profile else None
    if spec.model_profile and model is None:
        raise CompilerError(f"Workflow {spec.id} references missing model {spec.model_profile}")
    if model is not None and model.family != spec.family:
        raise CompilerError(
            f"Workflow {spec.id} family {spec.family!r} does not match model family {model.family!r}"
        )

    if spec.kind == "upscale":
        graph = WorkflowGraph.from_ui_json(_build_upscale(spec))
    else:
        graph = load_template(root / spec.template)
        _apply_spec(graph, spec, model)

    _set_app_mode(graph, spec)
    validate_ui_graph(graph)
    app = graph.data
    ui = _without_app_mode(app) if spec.id in UI_OUTPUTS else None
    api_prompt = _compile_api_prompt(root, spec, model) if spec.id in API_OUTPUTS else None
    return CompiledWorkflow(spec, app, ui, api_prompt)


def _apply_spec(graph: WorkflowGraph, spec: WorkflowSpec, model: ModelProfile | None) -> None:
    if model is not None:
        if model.family == "sdxl":
            _apply_sdxl(graph, spec, model)
        elif model.family == "z-image":
            _apply_z_image(graph, spec, model)
        elif model.family == "flux2":
            _apply_flux2(graph, spec, model)
        else:
            raise CompilerError(f"Unsupported model family: {model.family}")

    if spec.kind == "sdxl-control":
        _apply_control_variant(graph, spec)
    _set_widget_if_present(graph, "save_image", "filename_prefix", spec.defaults.get("filenamePrefix"))


def _apply_sdxl(graph: WorkflowGraph, spec: WorkflowSpec, model: ModelProfile) -> None:
    _set_widget(graph, "checkpoint", "ckpt_name", _loader_name(model.components["checkpoint"], "checkpoints/"))
    _set_widget(graph, "positive_prompt", "text", spec.defaults["positivePrompt"])
    _set_widget(graph, "negative_prompt", "text", spec.defaults["negativePrompt"])
    _set_widget_if_present(graph, "latent", "width", 1024)
    _set_widget_if_present(graph, "latent", "height", 1024)
    _set_sampling(graph, model, int(spec.defaults.get("seed", 246813579)))
    _set_widget_if_present(graph, "resolution", "preset", spec.defaults.get("resolution"))
    _set_widget_if_present(graph, "control_apply", "strength", spec.defaults.get("strength"))


def _apply_z_image(graph: WorkflowGraph, spec: WorkflowSpec, model: ModelProfile) -> None:
    _set_widget(graph, "diffusion_loader", "unet_name", _loader_name(model.components["diffusion"], "diffusion_models/"))
    _set_widget(graph, "text_encoder_loader", "clip_name", _loader_name(model.components["textEncoder"], "text_encoders/"))
    _set_widget(graph, "vae_loader", "vae_name", _loader_name(model.components["vae"], "vae/"))
    prompt_key = "prompt_encoder" if spec.kind == "z-create" else "positive_prompt"
    _set_widget(graph, prompt_key, "text", spec.defaults["positivePrompt"])
    _set_widget_if_present(graph, "latent", "width", 1024)
    _set_widget_if_present(graph, "latent", "height", 1024)
    _set_sampling(graph, model, int(spec.defaults.get("seed", 246813579)))


def _apply_flux2(graph: WorkflowGraph, spec: WorkflowSpec, model: ModelProfile) -> None:
    _set_widget(graph, "diffusion_loader", "unet_name", _loader_name(model.components["diffusion"], "diffusion_models/"))
    _set_widget(graph, "text_encoder_loader", "clip_name", _loader_name(model.components["textEncoder"], "text_encoders/"))
    _set_widget(graph, "vae_loader", "vae_name", _loader_name(model.components["vae"], "vae/"))
    _set_widget(graph, "positive_prompt", "text", spec.defaults["positivePrompt"])
    _set_widget(graph, "width", "value", 1024)
    _set_widget(graph, "height", "value", 1024)
    _set_widget(graph, "noise", "noise_seed", int(spec.defaults.get("seed", 246813579)))
    _set_widget_if_present(graph, "scheduler", "steps", model.sampling.steps)
    _set_widget_if_present(graph, "sampler_select", "sampler_name", model.sampling.sampler)
    _set_widget_if_present(graph, "guider", "cfg", model.sampling.cfg)


def _set_sampling(graph: WorkflowGraph, model: ModelProfile, seed: int) -> None:
    _set_widget(graph, "sampler", "seed", seed)
    _set_widget(graph, "sampler", "steps", model.sampling.steps)
    _set_widget(graph, "sampler", "cfg", model.sampling.cfg)
    _set_widget(graph, "sampler", "sampler_name", model.sampling.sampler)
    _set_widget(graph, "sampler", "scheduler", model.sampling.scheduler)


def _apply_control_variant(graph: WorkflowGraph, spec: WorkflowSpec) -> None:
    mode = spec.variant["preprocessor"]
    preprocessor = graph.find_one(studio_key="preprocessor").node
    variants = {
        "canny": ("CannyEdgePreprocessor", [100, 200, 1024], ["low_threshold", "high_threshold", "resolution"]),
        "depth": ("DepthAnythingV2Preprocessor", ["depth_anything_v2_vits.pth", 1024], ["model", "resolution"]),
        "pose": (
            "DWPreprocessor",
            ["enable", "enable", "enable", 1024, "yolox_l.torchscript.pt", "dw-ll_ucoco_384_bs5.torchscript.pt", "disable"],
            ["detect_hand", "detect_body", "detect_face", "resolution", "bbox_detector", "pose_estimator", "scale_stick_for_xinsr_cn"],
        ),
    }
    if mode not in variants:
        raise CompilerError(f"Unknown SDXL control preprocessor: {mode}")
    node_type, values, widgets = variants[mode]
    preprocessor["type"] = node_type
    preprocessor["widgets_values"] = values
    preprocessor["properties"]["studio_widgets"] = widgets
    _set_widget(graph, "union_type", "type", spec.variant["unionType"])


def _build_upscale(spec: WorkflowSpec) -> dict[str, Any]:
    builder = GraphBuilder()
    image = builder.add(
        "LoadImage",
        key="input_image",
        outputs={"IMAGE": "IMAGE", "MASK": "MASK"},
        widgets={"image": "studio-reference.webp", "upload": "image"},
    )
    loader = builder.add(
        "UpscaleModelLoader",
        key="upscale_loader",
        outputs={"UPSCALE_MODEL": "UPSCALE_MODEL"},
        widgets={"model_name": spec.variant["upscaleModel"]},
    )
    upscale = builder.add(
        "ImageUpscaleWithModel",
        key="upscale",
        inputs={"upscale_model": loader.output("UPSCALE_MODEL"), "image": image.output("IMAGE")},
        input_types={"upscale_model": "UPSCALE_MODEL", "image": "IMAGE"},
        outputs={"IMAGE": "IMAGE"},
    )
    save = builder.add(
        "SaveImage",
        key="save_image",
        inputs={"images": upscale.output("IMAGE")},
        input_types={"images": "IMAGE"},
        widgets={"filename_prefix": spec.defaults["filenamePrefix"]},
    )
    return builder.to_ui_workflow(app_inputs=[(image, "image")], app_outputs=[save])


def _set_app_mode(graph: WorkflowGraph, spec: WorkflowSpec) -> None:
    inputs: list[list[Any]] = []
    for value in spec.exposed_inputs:
        node = graph.find_one(studio_key=value.node)
        node_id: Any = node.id if node.scope is None else node.app_id
        inputs.append([node_id, value.widget])
    output = graph.find_one(studio_key=spec.output_key)
    if output.scope is not None:
        raise CompilerError(f"Workflow {spec.id} output must be a root node")
    extra = graph.data.setdefault("extra", {})
    extra["linearMode"] = True
    extra["linearData"] = {"inputs": inputs, "outputs": [output.id]}


def _without_app_mode(value: dict[str, Any]) -> dict[str, Any]:
    result = deepcopy(value)
    extra = result.setdefault("extra", {})
    extra.pop("linearMode", None)
    extra.pop("linearData", None)
    return result


def _set_widget(graph: WorkflowGraph, key: str, widget: str, value: Any) -> None:
    node = graph.find_one(studio_key=key).node
    widgets = node.get("properties", {}).get("studio_widgets", [])
    if widget not in widgets:
        raise CompilerError(f"Node {key!r} does not declare widget {widget!r}")
    index = widgets.index(widget)
    values = node.setdefault("widgets_values", [])
    if index >= len(values):
        raise CompilerError(f"Node {key!r} widget {widget!r} has no serialized value")
    values[index] = value


def _set_widget_if_present(graph: WorkflowGraph, key: str, widget: str, value: Any) -> None:
    if value is None:
        return
    try:
        node = graph.find_one(studio_key=key)
    except ValueError:
        return
    widgets = node.node.get("properties", {}).get("studio_widgets", [])
    if widget in widgets:
        _set_widget(graph, key, widget, value)


def _compile_api_prompt(root: Path, spec: WorkflowSpec, model: ModelProfile | None) -> dict[str, Any] | None:
    if model is None:
        return None
    template_name = {"sdxl": "sdxl.json", "z-image": "z_image.json", "flux2": "flux2.json"}[model.family]
    prompt = ApiPromptGraph.load(root / "vendor" / "api" / template_name)
    seed = int(spec.defaults.get("seed", 246813579))
    prefix = spec.defaults.get("filenamePrefix", spec.id)

    if model.family == "sdxl":
        prompt.set_input("checkpoint", "ckpt_name", _loader_name(model.components["checkpoint"], "checkpoints/"))
        prompt.set_input("positive_prompt", "text", spec.defaults["positivePrompt"])
        prompt.set_input("negative_prompt", "text", spec.defaults["negativePrompt"])
        prompt.set_input("latent", "width", 1024)
        prompt.set_input("latent", "height", 1024)
        for name, value in _sampling_inputs(model, seed).items():
            prompt.set_input("sampler", name, value)
    elif model.family == "z-image":
        _set_api_components(prompt, model)
        prompt.set_input("positive_prompt", "text", spec.defaults["positivePrompt"])
        prompt.set_input("latent", "width", 1024)
        prompt.set_input("latent", "height", 1024)
        for name, value in _sampling_inputs(model, seed).items():
            prompt.set_input("sampler", name, value)
    elif model.family == "flux2":
        _set_api_components(prompt, model)
        prompt.set_input("positive_prompt", "text", spec.defaults["positivePrompt"])
        prompt.set_input("guider", "cfg", model.sampling.cfg)
        prompt.set_input("noise", "noise_seed", seed)
        prompt.set_input("sampler_select", "sampler_name", model.sampling.sampler)
        prompt.set_input("scheduler", "steps", model.sampling.steps)
        prompt.set_input("scheduler", "width", 1024)
        prompt.set_input("scheduler", "height", 1024)
        prompt.set_input("latent", "width", 1024)
        prompt.set_input("latent", "height", 1024)
    prompt.set_input("save_image", "filename_prefix", prefix)
    prompt.validate()
    return prompt.data


def _set_api_components(prompt: ApiPromptGraph, model: ModelProfile) -> None:
    prompt.set_input("diffusion_loader", "unet_name", _loader_name(model.components["diffusion"], "diffusion_models/"))
    prompt.set_input("text_encoder_loader", "clip_name", _loader_name(model.components["textEncoder"], "text_encoders/"))
    prompt.set_input("vae_loader", "vae_name", _loader_name(model.components["vae"], "vae/"))


def _sampling_inputs(model: ModelProfile, seed: int) -> dict[str, Any]:
    return {
        "seed": seed,
        "steps": model.sampling.steps,
        "cfg": model.sampling.cfg,
        "sampler_name": model.sampling.sampler,
        "scheduler": model.sampling.scheduler,
    }


def _loader_name(component: str, prefix: str) -> str:
    normalized = component.replace("\\", "/")
    if not normalized.startswith(prefix):
        raise CompilerError(f"Component {component!r} does not belong under {prefix!r}")
    return normalized[len(prefix):].replace("/", "\\")


def _write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    temporary.replace(path)
