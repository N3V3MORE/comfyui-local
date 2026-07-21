from __future__ import annotations

import argparse
from pathlib import Path

from .compiler import compile_catalog


def main() -> int:
    parser = argparse.ArgumentParser(prog="python -m comfy_local")
    commands = parser.add_subparsers(dest="command", required=True)
    compile_parser = commands.add_parser("compile", help="compile all declared workflows")
    compile_parser.add_argument("--root", type=Path, required=True, help="project root")
    compile_parser.add_argument("--output-root", type=Path, required=True, help="output root")
    args = parser.parse_args()

    if args.command == "compile":
        result = compile_catalog(args.root.resolve(), args.output_root.resolve())
        print(
            f"Compiled {len(result.apps)} apps, "
            f"{len(result.ui_workflows)} UI workflows, and {len(result.api_prompts)} API prompts"
        )
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
