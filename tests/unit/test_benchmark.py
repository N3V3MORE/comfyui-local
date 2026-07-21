from __future__ import annotations

import sys
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "src"))

from comfy_local.api_prompt import ApiPromptGraph
from comfy_local.benchmark import BenchmarkError, materialize_prompt
from comfy_local.manifests import load_models


class BenchmarkPromptTests(unittest.TestCase):
    def test_every_model_materializes_by_semantic_key(self) -> None:
        for model_id in load_models(PROJECT_ROOT):
            with self.subTest(model=model_id):
                value = materialize_prompt(
                    PROJECT_ROOT,
                    model_id=model_id,
                    width=1216,
                    height=832,
                    seed=42,
                    filename_prefix=f"proof/{model_id}",
                )
                graph = ApiPromptGraph(value)
                graph.validate()
                self.assertEqual(1216, graph.find_one("latent")["inputs"]["width"])
                self.assertEqual(832, graph.find_one("latent")["inputs"]["height"])
                self.assertEqual(
                    f"proof/{model_id}",
                    graph.find_one("save_image")["inputs"]["filename_prefix"],
                )

    def test_unknown_model_is_rejected(self) -> None:
        with self.assertRaisesRegex(BenchmarkError, "Unknown model"):
            materialize_prompt(
                PROJECT_ROOT,
                model_id="missing",
                width=1024,
                height=1024,
                seed=1,
                filename_prefix="proof/missing",
            )

    def test_dimensions_must_be_positive_multiples_of_64(self) -> None:
        with self.assertRaisesRegex(BenchmarkError, "multiples of 64"):
            materialize_prompt(
                PROJECT_ROOT,
                model_id="realvis-xl-v5",
                width=1000,
                height=1024,
                seed=1,
                filename_prefix="proof/invalid",
            )


if __name__ == "__main__":
    unittest.main()
