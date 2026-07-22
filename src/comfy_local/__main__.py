from __future__ import annotations

import argparse
import json
from dataclasses import asdict
from pathlib import Path

from .benchmark import (
    build_benchmark_plan,
    find_benchmark_job,
    materialize_prompt,
    materialize_scenario_prompt,
)
from .compiler import compile_catalog
from .graph import WorkflowGraph
from .validation import validate_ui_graph


def main() -> int:
    parser = argparse.ArgumentParser(prog="python -m comfy_local")
    commands = parser.add_subparsers(dest="command", required=True)
    compile_parser = commands.add_parser("compile", help="compile all declared workflows")
    compile_parser.add_argument("--root", type=Path, required=True, help="project root")
    compile_parser.add_argument("--output-root", type=Path, required=True, help="output root")
    validate_parser = commands.add_parser("validate-ui", help="validate serialized UI workflows")
    validate_parser.add_argument("--path", type=Path, action="append", required=True)
    prompt_parser = commands.add_parser("prompt", help="materialize one benchmark API prompt")
    prompt_parser.add_argument("--root", type=Path, required=True)
    prompt_parser.add_argument("--model-id", required=True)
    prompt_parser.add_argument("--width", type=int, required=True)
    prompt_parser.add_argument("--height", type=int, required=True)
    prompt_parser.add_argument("--seed", type=int, required=True)
    prompt_parser.add_argument("--filename-prefix", required=True)
    prompt_parser.add_argument("--output", type=Path, required=True)
    plan_parser = commands.add_parser("benchmark-plan", help="write a performance or quality job plan")
    plan_parser.add_argument("--root", type=Path, required=True)
    plan_parser.add_argument("--suite", choices=("performance", "quality"), required=True)
    plan_parser.add_argument("--output", type=Path, required=True)
    scenario_parser = commands.add_parser("scenario-prompt", help="materialize a planned benchmark prompt")
    scenario_parser.add_argument("--root", type=Path, required=True)
    scenario_parser.add_argument("--suite", choices=("performance", "quality"), required=True)
    scenario_parser.add_argument("--scenario-id", required=True)
    scenario_parser.add_argument("--model-id", required=True)
    scenario_parser.add_argument("--seed", type=int, required=True)
    scenario_parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    if args.command == "compile":
        result = compile_catalog(args.root.resolve(), args.output_root.resolve())
        print(
            f"Compiled {len(result.apps)} apps, "
            f"{len(result.ui_workflows)} UI workflows, and {len(result.api_prompts)} API prompts"
        )
        return 0
    if args.command == "validate-ui":
        for path in args.path:
            value = json.loads(path.read_text(encoding="utf-8"))
            validate_ui_graph(WorkflowGraph.from_ui_json(value))
        return 0
    if args.command == "prompt":
        value = materialize_prompt(
            args.root.resolve(),
            model_id=args.model_id,
            width=args.width,
            height=args.height,
            seed=args.seed,
            filename_prefix=args.filename_prefix,
        )
        _write_json(args.output, value)
        return 0
    if args.command == "benchmark-plan":
        _write_json(args.output, [asdict(job) for job in build_benchmark_plan(args.root.resolve(), args.suite)])
        return 0
    if args.command == "scenario-prompt":
        job = find_benchmark_job(
            args.root.resolve(),
            suite=args.suite,
            scenario_id=args.scenario_id,
            model_id=args.model_id,
            seed=args.seed,
        )
        _write_json(args.output, materialize_scenario_prompt(args.root.resolve(), job))
        return 0
    return 2


def _write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


if __name__ == "__main__":
    raise SystemExit(main())
