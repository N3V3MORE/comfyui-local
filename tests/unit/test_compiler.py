import json
import sys
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "src"))

from comfy_local.compiler import CompilerError, compile_catalog, compile_spec
from comfy_local.graph import WorkflowGraph
from comfy_local.manifests import load_models, load_workflow_specs
from comfy_local.validation import validate_ui_graph


class WorkflowCompilerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.models = load_models(PROJECT_ROOT)
        self.specs = {spec.id: spec for spec in load_workflow_specs(PROJECT_ROOT)}

    def test_sdxl_app_uses_model_profile_and_semantic_app_inputs(self) -> None:
        spec = self.specs["realvis-xl"]
        compiled = compile_spec(PROJECT_ROOT, spec, self.models)
        graph = WorkflowGraph.from_ui_json(compiled.app)

        validate_ui_graph(graph)
        checkpoint = graph.find_one(studio_key="checkpoint")
        positive = graph.find_one(studio_key="positive_prompt")
        sampler = graph.find_one(studio_key="sampler")
        self.assertEqual(r"realistic\RealVisXL_V5.0_fp16.safetensors", checkpoint.node["widgets_values"][0])
        self.assertIn("London street", positive.node["widgets_values"][0])
        self.assertEqual(30, sampler.node["widgets_values"][2])
        self.assertEqual(
            [(graph.find_one(studio_key=item.node).app_id, item.widget) for item in spec.exposed_inputs],
            [(str(node_id), widget) for node_id, widget in graph.data["extra"]["linearData"]["inputs"]],
        )

    def test_model_family_mismatch_fails_before_template_mutation(self) -> None:
        invalid = replace(self.specs["realvis-xl"], family="z-image")
        with self.assertRaisesRegex(CompilerError, "family"):
            compile_spec(PROJECT_ROOT, invalid, self.models)

    def test_all_catalog_outputs_are_valid_and_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            first_result = compile_catalog(PROJECT_ROOT, Path(first))
            second_result = compile_catalog(PROJECT_ROOT, Path(second))

            self.assertEqual(15, len(first_result.apps))
            self.assertEqual(4, len(first_result.ui_workflows))
            self.assertEqual(3, len(first_result.api_prompts))
            self.assertEqual(first_result.relative_files, second_result.relative_files)
            for relative in first_result.relative_files:
                first_bytes = (Path(first) / relative).read_bytes()
                second_bytes = (Path(second) / relative).read_bytes()
                self.assertEqual(first_bytes, second_bytes, relative)

            for relative in first_result.apps:
                workflow = json.loads((Path(first) / relative).read_text(encoding="utf-8"))
                validate_ui_graph(WorkflowGraph.from_ui_json(workflow))

    def test_upscale_graph_is_built_from_handles(self) -> None:
        compiled = compile_spec(PROJECT_ROOT, self.specs["upscale-photo-4x"], self.models)
        graph = WorkflowGraph.from_ui_json(compiled.app)

        self.assertEqual("RealESRGAN_x4plus.pth", graph.find_one(studio_key="upscale_loader").node["widgets_values"][0])
        validate_ui_graph(graph)


if __name__ == "__main__":
    unittest.main()
