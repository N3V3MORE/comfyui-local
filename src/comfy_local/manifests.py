from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any

from jsonschema import Draft202012Validator


class ConfigurationError(ValueError):
    pass


@dataclass(frozen=True)
class SamplingProfile:
    steps: int
    cfg: float
    sampler: str
    scheduler: str


@dataclass(frozen=True)
class ModelProfile:
    id: str
    name: str
    category: str
    family: str
    parameters: str
    precision: str
    artifact_ids: tuple[str, ...]
    components: dict[str, str]
    sampling: SamplingProfile


@dataclass(frozen=True)
class Artifact:
    id: str
    target: str
    url: str
    bytes: int
    sha256: str
    role: str
    metadata: dict[str, Any]


@dataclass(frozen=True)
class AppInput:
    node: str
    widget: str


@dataclass(frozen=True)
class WorkflowSpec:
    id: str
    name: str
    group: str
    family: str
    kind: str
    template: str
    model_profile: str | None
    output: str
    purpose: str
    support_artifacts: tuple[str, ...]
    exposed_inputs: tuple[AppInput, ...]
    output_key: str
    defaults: dict[str, Any]
    variant: dict[str, Any]


def load_models(root: Path) -> dict[str, ModelProfile]:
    values = _read(root / "config" / "models.json")["models"]
    result: dict[str, ModelProfile] = {}
    for value in values:
        sampling = value["sampling"]
        model = ModelProfile(
            id=value["id"],
            name=value["name"],
            category=value["category"],
            family=value["family"],
            parameters=value["parameters"],
            precision=value["precision"],
            artifact_ids=tuple(value["artifactIds"]),
            components=dict(value["components"]),
            sampling=SamplingProfile(
                steps=int(sampling["steps"]),
                cfg=float(sampling["cfg"]),
                sampler=sampling["sampler"],
                scheduler=sampling["scheduler"],
            ),
        )
        _add_unique(result, model.id, model, "model")
    return result


def load_artifacts(root: Path) -> dict[str, Artifact]:
    values = _read(root / "config" / "artifacts.json")["artifacts"]
    result: dict[str, Artifact] = {}
    for value in values:
        artifact = Artifact(
            id=value["id"],
            target=_posix(value["target"]),
            url=value["url"],
            bytes=int(value["bytes"]),
            sha256=value["sha256"].lower(),
            role=value["role"],
            metadata={key: item for key, item in value.items() if key not in {"id", "target", "url", "bytes", "sha256", "role"}},
        )
        _add_unique(result, artifact.id, artifact, "artifact")
    return result


def load_workflow_specs(root: Path) -> tuple[WorkflowSpec, ...]:
    values = _read(root / "config" / "workflow-specs.json")["apps"]
    result: list[WorkflowSpec] = []
    ids: set[str] = set()
    for value in values:
        if value["id"] in ids:
            raise ConfigurationError(f"Duplicate workflow specification id: {value['id']}")
        ids.add(value["id"])
        result.append(
            WorkflowSpec(
                id=value["id"],
                name=value["name"],
                group=value["group"],
                family=value["family"],
                kind=value["kind"],
                template=_posix(value["template"]),
                model_profile=value.get("modelProfile"),
                output=_posix(value["output"]),
                purpose=value["purpose"],
                support_artifacts=tuple(value.get("supportArtifacts", [])),
                exposed_inputs=tuple(AppInput(**item) for item in value["exposedInputs"]),
                output_key=value["outputKey"],
                defaults=dict(value.get("defaults", {})),
                variant=dict(value.get("variant", {})),
            )
        )
    return tuple(result)


def load_resolutions(root: Path) -> dict[str, tuple[int, int]]:
    values = _read(root / "config" / "resolutions.json")["resolutions"]
    result: dict[str, tuple[int, int]] = {}
    for value in values:
        label = value["label"]
        if label in result:
            raise ConfigurationError(f"Duplicate resolution label: {label}")
        result[label] = int(value["width"]), int(value["height"])
    return result


def validate_configuration(root: Path) -> None:
    _validate_schemas(root)
    models = load_models(root)
    artifacts = load_artifacts(root)
    specs = load_workflow_specs(root)
    artifact_targets = {artifact.target for artifact in artifacts.values()}
    allowed_families = {"sdxl", "z-image", "flux2", "upscale"}

    for artifact in artifacts.values():
        _require_relative(artifact.target, f"artifact {artifact.id}")
        if artifact.role not in {"core", "support"}:
            raise ConfigurationError(f"Artifact {artifact.id} has invalid role {artifact.role!r}")
        if artifact.bytes <= 0 or len(artifact.sha256) != 64:
            raise ConfigurationError(f"Artifact {artifact.id} has invalid integrity metadata")

    for model in models.values():
        if model.family not in allowed_families - {"upscale"}:
            raise ConfigurationError(f"Model {model.id} has unknown family {model.family!r}")
        for artifact_id in model.artifact_ids:
            if artifact_id not in artifacts or artifacts[artifact_id].role != "core":
                raise ConfigurationError(f"Model {model.id} references undeclared core artifact {artifact_id}")
        for component in model.components.values():
            if _posix(component) not in artifact_targets:
                raise ConfigurationError(f"Model {model.id} component is not declared: {component}")

    for spec in specs:
        if spec.family not in allowed_families:
            raise ConfigurationError(f"Workflow {spec.id} has unknown family {spec.family!r}")
        _require_relative(spec.template, f"workflow {spec.id} template")
        _require_relative(spec.output, f"workflow {spec.id} output")
        if spec.model_profile:
            model = models.get(spec.model_profile)
            if model is None:
                raise ConfigurationError(f"Workflow {spec.id} references missing model {spec.model_profile}")
            if model.family != spec.family:
                raise ConfigurationError(f"Workflow {spec.id} mixes {spec.family} with {model.family}")
        for artifact_id in spec.support_artifacts:
            if artifact_id not in artifacts or artifacts[artifact_id].role != "support":
                raise ConfigurationError(f"Workflow {spec.id} references undeclared support artifact {artifact_id}")
        exposed = [(item.node, item.widget) for item in spec.exposed_inputs]
        if len(exposed) != len(set(exposed)):
            raise ConfigurationError(f"Workflow {spec.id} has duplicate exposed inputs")

    resolutions = load_resolutions(root)
    if len(resolutions) != 7:
        raise ConfigurationError(f"Expected seven resolutions; found {len(resolutions)}")

    licenses = _read(root / "config" / "licenses.json")
    if set(licenses.get("models", {})) != set(models):
        raise ConfigurationError("Model license records do not match model profiles")
    support_ids = {item.id for item in artifacts.values() if item.role == "support"}
    if set(licenses.get("supportArtifacts", {})) != support_ids:
        raise ConfigurationError("Support license records do not match support artifacts")


def _validate_schemas(root: Path) -> None:
    names = (
        "models.json",
        "artifacts.json",
        "workflow-specs.json",
        "resolutions.json",
        "benchmark-scenarios.json",
        "licenses.json",
        "model-aliases.json",
    )
    for name in names:
        instance = _read(root / "config" / name)
        schema = _read_schema(root / "config" / "schemas" / name)
        errors = sorted(Draft202012Validator(schema).iter_errors(instance), key=lambda item: list(item.path))
        if errors:
            location = ".".join(str(item) for item in errors[0].path) or "root"
            raise ConfigurationError(f"{name} schema validation failed at {location}: {errors[0].message}")


def _read(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ConfigurationError(f"Could not read configuration {path}: {error}") from error
    if not isinstance(value, dict) or value.get("version") != 1:
        raise ConfigurationError(f"Unsupported configuration version in {path}")
    return value


def _read_schema(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ConfigurationError(f"Could not read schema {path}: {error}") from error
    Draft202012Validator.check_schema(value)
    return value


def _add_unique(target: dict[str, Any], key: str, value: Any, kind: str) -> None:
    if key in target:
        raise ConfigurationError(f"Duplicate {kind} id: {key}")
    target[key] = value


def _posix(value: str) -> str:
    return value.replace("\\", "/")


def _require_relative(value: str, label: str) -> None:
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts:
        raise ConfigurationError(f"{label} must be a safe relative path")
