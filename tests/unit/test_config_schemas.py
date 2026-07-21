from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator


PROJECT_ROOT = Path(__file__).resolve().parents[2]
CONFIG_ROOT = PROJECT_ROOT / "config"


class ConfigSchemaTests(unittest.TestCase):
    FILES = (
        "models.json",
        "artifacts.json",
        "workflow-specs.json",
        "resolutions.json",
        "benchmark-scenarios.json",
        "licenses.json",
        "model-aliases.json",
    )

    def test_every_focused_config_matches_its_schema(self) -> None:
        for name in self.FILES:
            with self.subTest(config=name):
                instance = json.loads((CONFIG_ROOT / name).read_text(encoding="utf-8"))
                schema = json.loads((CONFIG_ROOT / "schemas" / name).read_text(encoding="utf-8"))
                Draft202012Validator.check_schema(schema)
                errors = sorted(Draft202012Validator(schema).iter_errors(instance), key=lambda item: list(item.path))
                self.assertEqual([], [error.message for error in errors])

    def test_model_schema_rejects_an_unknown_family(self) -> None:
        instance = json.loads((CONFIG_ROOT / "models.json").read_text(encoding="utf-8"))
        schema = json.loads((CONFIG_ROOT / "schemas" / "models.json").read_text(encoding="utf-8"))
        invalid = copy.deepcopy(instance)
        invalid["models"][0]["family"] = "mixed-family"

        errors = list(Draft202012Validator(schema).iter_errors(invalid))
        self.assertTrue(any("not one of" in error.message for error in errors))


if __name__ == "__main__":
    unittest.main()
