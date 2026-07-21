from __future__ import annotations

import json
from pathlib import Path

from .graph import WorkflowGraph


def load_template(path: Path) -> WorkflowGraph:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"Could not load workflow template {path}: {error}") from error
    return WorkflowGraph.from_ui_json(value)
