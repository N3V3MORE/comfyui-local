import json
import sys
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "src"))

from comfy_local.normalization import normalize_workflow


class WorkflowSnapshotTests(unittest.TestCase):
    def test_committed_workflows_match_normalized_snapshots(self) -> None:
        roots = {
            "apps": PROJECT_ROOT / "workflows" / "apps",
            "ui": PROJECT_ROOT / "workflows" / "ui",
            "api": PROJECT_ROOT / "workflows" / "api",
        }

        for kind, root in roots.items():
            for workflow_path in sorted(root.rglob("*.json")):
                relative = workflow_path.relative_to(root)
                snapshot_path = PROJECT_ROOT / "tests" / "snapshots" / kind / relative
                with self.subTest(kind=kind, workflow=str(relative)):
                    actual = normalize_workflow(json.loads(workflow_path.read_text(encoding="utf-8")))
                    expected = json.loads(snapshot_path.read_text(encoding="utf-8"))
                    self.assertEqual(expected, actual)


if __name__ == "__main__":
    unittest.main()
