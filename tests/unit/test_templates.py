import sys
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "src"))

from comfy_local.manifests import load_workflow_specs
from comfy_local.templates import load_template
from comfy_local.validation import validate_ui_graph


class CanonicalTemplateTests(unittest.TestCase):
    def test_every_spec_resolves_semantic_controls_exactly_once(self) -> None:
        specs = load_workflow_specs(PROJECT_ROOT)

        for spec in specs:
            graph = load_template(PROJECT_ROOT / spec.template)
            with self.subTest(spec=spec.id):
                for app_input in spec.exposed_inputs:
                    node = graph.find_one(studio_key=app_input.node)
                    self.assertIn(app_input.widget, node.node["properties"]["studio_widgets"])
                graph.find_one(studio_key=spec.output_key)

    def test_vendored_templates_are_valid_and_do_not_own_app_metadata(self) -> None:
        paths = {PROJECT_ROOT / spec.template for spec in load_workflow_specs(PROJECT_ROOT)}
        self.assertEqual(8, len(paths))

        for path in paths:
            graph = load_template(path)
            with self.subTest(template=path.name):
                validate_ui_graph(graph)
                self.assertNotIn("linearData", graph.data.get("extra", {}))


if __name__ == "__main__":
    unittest.main()
