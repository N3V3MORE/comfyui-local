import sys
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "src"))

from comfy_local.builder import GraphBuilder, GraphBuilderError
from comfy_local.graph import WorkflowGraph
from comfy_local.validation import validate_ui_graph


class GraphBuilderTests(unittest.TestCase):
    def test_handles_connect_nodes_without_exposing_numeric_ids(self) -> None:
        builder = GraphBuilder()
        source = builder.add("Source", key="source", outputs={"IMAGE": "IMAGE"})
        save = builder.add(
            "SaveImage",
            key="save_image",
            inputs={"images": source.output("IMAGE")},
            input_types={"images": "IMAGE"},
            widgets={"filename_prefix": "proof"},
        )

        self.assertFalse(hasattr(source, "id"))
        workflow = builder.to_ui_workflow(app_inputs=[(save, "filename_prefix")], app_outputs=[save])
        validate_ui_graph(WorkflowGraph.from_ui_json(workflow))
        self.assertEqual([[2, "filename_prefix"]], workflow["extra"]["linearData"]["inputs"])
        self.assertEqual([2], workflow["extra"]["linearData"]["outputs"])

    def test_duplicate_semantic_keys_are_rejected_at_construction(self) -> None:
        builder = GraphBuilder()
        builder.add("Source", key="source")

        with self.assertRaisesRegex(GraphBuilderError, "Duplicate node key"):
            builder.add("Other", key="source")

    def test_serialization_is_deterministic(self) -> None:
        def build():
            builder = GraphBuilder()
            source = builder.add("Source", key="source", outputs={"VALUE": "INT"})
            sink = builder.add(
                "Sink",
                key="sink",
                inputs={"value": source.output("VALUE")},
                input_types={"value": "INT"},
            )
            return builder.to_ui_workflow(app_outputs=[sink])

        self.assertEqual(build(), build())

    def test_unknown_output_handle_is_rejected(self) -> None:
        builder = GraphBuilder()
        source = builder.add("Source", key="source", outputs={"VALUE": "INT"})

        with self.assertRaisesRegex(GraphBuilderError, "Unknown output"):
            source.output("IMAGE")


if __name__ == "__main__":
    unittest.main()
