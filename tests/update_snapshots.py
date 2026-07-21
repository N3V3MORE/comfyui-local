from __future__ import annotations

import json
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "src"))

from comfy_local.normalization import normalize_workflow


def main() -> None:
    roots = {
        "apps": PROJECT_ROOT / "workflows" / "apps",
        "ui": PROJECT_ROOT / "workflows" / "ui",
        "api": PROJECT_ROOT / "workflows" / "api",
    }
    for kind, root in roots.items():
        for workflow_path in sorted(root.rglob("*.json")):
            relative = workflow_path.relative_to(root)
            snapshot_path = PROJECT_ROOT / "tests" / "snapshots" / kind / relative
            snapshot_path.parent.mkdir(parents=True, exist_ok=True)
            value = normalize_workflow(json.loads(workflow_path.read_text(encoding="utf-8")))
            snapshot_path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
