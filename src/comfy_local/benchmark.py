from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .compiler import compile_api_prompt
from .manifests import load_models, load_workflow_specs


class BenchmarkError(ValueError):
    pass


@dataclass(frozen=True)
class BenchmarkJob:
    suite: str
    scenario_id: str
    model_id: str
    width: int
    height: int
    seed: int
    run_kind: str
    prompt: str
    negative_prompt: str
    filename_prefix: str


def build_benchmark_plan(root: Path, suite: str) -> tuple[BenchmarkJob, ...]:
    if suite not in {"performance", "quality"}:
        raise BenchmarkError(f"Unknown benchmark suite: {suite}")
    scenarios = _load_scenarios(root).get(suite, [])
    models = load_models(root)
    jobs: list[BenchmarkJob] = []

    for scenario in scenarios:
        width, height = (int(value) for value in scenario["dimensions"])
        for model in models.values():
            if model.family not in scenario["families"]:
                continue
            categories = scenario.get("categories")
            if categories and model.category not in categories:
                continue
            for index, seed in enumerate(scenario["seeds"]):
                run_kind = "cold" if suite == "performance" and index == 0 else suite
                if suite == "performance" and index > 0:
                    run_kind = "warm"
                prefix = f"benchmark/{suite}/{scenario['id']}/{model.id}/{seed}"
                jobs.append(
                    BenchmarkJob(
                        suite=suite,
                        scenario_id=scenario["id"],
                        model_id=model.id,
                        width=width,
                        height=height,
                        seed=int(seed),
                        run_kind=run_kind,
                        prompt=scenario["prompt"],
                        negative_prompt=scenario.get("negativePrompt", ""),
                        filename_prefix=prefix,
                    )
                )
    return tuple(jobs)


def materialize_scenario_prompt(root: Path, job: BenchmarkJob) -> dict[str, Any]:
    return materialize_prompt(
        root,
        model_id=job.model_id,
        width=job.width,
        height=job.height,
        seed=job.seed,
        filename_prefix=job.filename_prefix,
        positive_prompt=job.prompt,
        negative_prompt=job.negative_prompt,
    )


def find_benchmark_job(
    root: Path,
    *,
    suite: str,
    scenario_id: str,
    model_id: str,
    seed: int,
) -> BenchmarkJob:
    matches = [
        job
        for job in build_benchmark_plan(root, suite)
        if job.scenario_id == scenario_id and job.model_id == model_id and job.seed == seed
    ]
    if len(matches) != 1:
        raise BenchmarkError(
            f"Benchmark job matched {len(matches)} records; expected one: "
            f"{suite}/{scenario_id}/{model_id}/{seed}"
        )
    return matches[0]


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


def _load_scenarios(root: Path) -> dict[str, Any]:
    path = root / "config" / "benchmark-scenarios.json"
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise BenchmarkError(f"Could not load benchmark scenarios: {error}") from error
