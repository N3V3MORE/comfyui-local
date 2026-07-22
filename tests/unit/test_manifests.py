import sys
import json
import shutil
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "src"))

from comfy_local.manifests import (
    load_artifacts,
    load_models,
    load_resolutions,
    load_workflow_specs,
    validate_configuration,
)


class FocusedManifestTests(unittest.TestCase):
    def test_models_are_behavior_only_and_family_typed(self) -> None:
        models = load_models(PROJECT_ROOT)

        self.assertEqual(6, len(models))
        self.assertEqual({"sdxl", "z-image", "flux2"}, {model.family for model in models.values()})
        self.assertFalse(hasattr(models["realvis-xl-v5"], "positive_prompt"))
        self.assertEqual("checkpoints/realistic/RealVisXL_V5.0_fp16.safetensors", models["realvis-xl-v5"].components["checkpoint"])
        self.assertEqual(4, models["flux2-klein-4b"].sampling.steps)

    def test_artifacts_are_unique_and_keep_core_support_roles(self) -> None:
        artifacts = load_artifacts(PROJECT_ROOT)

        self.assertEqual(21, len(artifacts))
        self.assertEqual(10, sum(artifact.role == "core" for artifact in artifacts.values()))
        self.assertEqual(11, sum(artifact.role == "support" for artifact in artifacts.values()))
        self.assertTrue(all(len(artifact.sha256) == 64 for artifact in artifacts.values()))
        self.assertTrue(all("license" not in artifact.metadata for artifact in artifacts.values()))

    def test_workflow_specs_resolve_models_and_support_assets(self) -> None:
        specs = load_workflow_specs(PROJECT_ROOT)
        models = load_models(PROJECT_ROOT)
        artifacts = load_artifacts(PROJECT_ROOT)

        self.assertEqual(15, len(specs))
        self.assertEqual(15, len({spec.id for spec in specs}))
        for spec in specs:
            if spec.model_profile:
                self.assertIn(spec.model_profile, models)
                self.assertEqual(spec.family, models[spec.model_profile].family)
            for artifact_id in spec.support_artifacts:
                self.assertIn(artifact_id, artifacts)
                self.assertEqual("support", artifacts[artifact_id].role)
            self.assertGreaterEqual(len(spec.exposed_inputs), 1)

    def test_every_model_component_is_declared_by_an_artifact(self) -> None:
        models = load_models(PROJECT_ROOT)
        artifact_targets = {artifact.target for artifact in load_artifacts(PROJECT_ROOT).values()}

        for model in models.values():
            for component in model.components.values():
                self.assertIn(component, artifact_targets, f"undeclared component for {model.id}: {component}")

    def test_resolutions_are_loaded_from_one_json_file(self) -> None:
        resolutions = load_resolutions(PROJECT_ROOT)

        self.assertEqual(7, len(resolutions))
        self.assertEqual((1024, 1024), resolutions["Square 1:1"])
        self.assertEqual((1344, 768), resolutions["Wide 16:9"])

    def test_complete_configuration_validates(self) -> None:
        validate_configuration(PROJECT_ROOT)

    def test_schema_violation_fails_before_cross_file_validation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            shutil.copytree(PROJECT_ROOT / "config", root / "config")
            path = root / "config" / "models.json"
            value = json.loads(path.read_text(encoding="utf-8"))
            value["models"][0]["unexpected"] = True
            path.write_text(json.dumps(value), encoding="utf-8")

            with self.assertRaisesRegex(Exception, "schema validation"):
                validate_configuration(root)

    def test_duplicate_artifact_targets_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            shutil.copytree(PROJECT_ROOT / "config", root / "config")
            path = root / "config" / "artifacts.json"
            value = json.loads(path.read_text(encoding="utf-8"))
            support_artifacts = [item for item in value["artifacts"] if item["role"] == "support"]
            support_artifacts[1]["target"] = support_artifacts[0]["target"]
            path.write_text(json.dumps(value), encoding="utf-8")

            with self.assertRaisesRegex(Exception, "Duplicate artifact target"):
                validate_configuration(root)

    def test_model_component_must_belong_to_its_declared_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            shutil.copytree(PROJECT_ROOT / "config", root / "config")
            path = root / "config" / "models.json"
            value = json.loads(path.read_text(encoding="utf-8"))
            value["models"][0]["components"]["checkpoint"] = value["models"][1]["components"]["checkpoint"]
            path.write_text(json.dumps(value), encoding="utf-8")

            with self.assertRaisesRegex(Exception, "does not belong to its declared artifacts"):
                validate_configuration(root)

    def test_workflow_kind_must_match_its_family(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            shutil.copytree(PROJECT_ROOT / "config", root / "config")
            path = root / "config" / "workflow-specs.json"
            value = json.loads(path.read_text(encoding="utf-8"))
            value["apps"][0]["kind"] = "upscale"
            path.write_text(json.dumps(value), encoding="utf-8")

            with self.assertRaisesRegex(Exception, "kind .* is incompatible"):
                validate_configuration(root)


if __name__ == "__main__":
    unittest.main()
