from __future__ import annotations

import argparse
import json
from pathlib import Path

from .benchmark import materialize_prompt
from .compiler import compile_catalog


def main() -> int:
    parser = argparse.ArgumentParser(prog="python -m comfy_local")
    commands = parser.add_subparsers(dest="command", required=True)
    compile_parser = commands.add_parser("compile", help="compile all declared workflows")
    compile_parser.add_argument("--root", type=Path, required=True, help="project root")
    compile_parser.add_argument("--output-root", type=Path, required=True, help="output root")
    prompt_parser = commands.add_parser("prompt", help="materialize one benchmark API prompt")
    prompt_parser.add_argument("--root", type=Path, required=True)
    prompt_parser.add_argument("--model-id", required=True)
    prompt_parser.add_argument("--width", type=int, required=True)
    prompt_parser.add_argument("--height", type=int, required=True)
    prompt_parser.add_argument("--seed", type=int, required=True)
    prompt_parser.add_argument("--filename-prefix", required=True)
    prompt_parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    if args.command == "compile":
        result = compile_catalog(args.root.resolve(), args.output_root.resolve())
        print(
            f"Compiled {len(result.apps)} apps, "
            f"{len(result.ui_workflows)} UI workflows, and {len(result.api_prompts)} API prompts"
        )
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
        args.output.parent.mkdir(parents=True, exist_ok=True)
        temporary = args.output.with_suffix(args.output.suffix + ".tmp")
        temporary.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
        temporary.replace(args.output)
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
