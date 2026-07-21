from __future__ import annotations

import sys
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "src"))

from comfy_local.api_prompt import ApiPromptGraph
from comfy_local.benchmark import (
    BenchmarkError,
    build_benchmark_plan,
    materialize_prompt,
    materialize_scenario_prompt,
)
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

    def test_performance_plan_marks_first_run_cold_and_repeats_warm(self) -> None:
        jobs = build_benchmark_plan(PROJECT_ROOT, "performance")
        self.assertGreater(len(jobs), 0)
        groups = {(job.scenario_id, job.model_id) for job in jobs}
        for scenario_id, model_id in groups:
            runs = [job for job in jobs if job.scenario_id == scenario_id and job.model_id == model_id]
            self.assertEqual(["cold", "warm", "warm"], [job.run_kind for job in runs])
            self.assertEqual(3, len({job.seed for job in runs}))

    def test_quality_plan_covers_declared_stress_scenarios(self) -> None:
        jobs = build_benchmark_plan(PROJECT_ROOT, "quality")
        scenario_ids = {job.scenario_id for job in jobs}
        self.assertTrue(
            {"composition-stress", "hands-and-faces", "embedded-text", "prompt-adherence"}
            <= scenario_ids
        )
        self.assertEqual({"quality"}, {job.run_kind for job in jobs})

    def test_scenario_prompt_uses_shared_prompt_dimensions_and_seed(self) -> None:
        job = next(
            job
            for job in build_benchmark_plan(PROJECT_ROOT, "quality")
            if job.scenario_id == "composition-stress" and job.model_id == "realvis-xl-v5"
        )
        graph = ApiPromptGraph(materialize_scenario_prompt(PROJECT_ROOT, job))

        self.assertEqual(job.prompt, graph.find_one("positive_prompt")["inputs"]["text"])
        self.assertEqual(job.width, graph.find_one("latent")["inputs"]["width"])
        self.assertEqual(job.height, graph.find_one("latent")["inputs"]["height"])

    def test_unknown_benchmark_suite_is_rejected(self) -> None:
        with self.assertRaisesRegex(BenchmarkError, "Unknown benchmark suite"):
            build_benchmark_plan(PROJECT_ROOT, "missing")


if __name__ == "__main__":
    unittest.main()
