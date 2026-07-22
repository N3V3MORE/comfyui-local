import sys
import unittest
from copy import deepcopy
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "src"))

from comfy_local.graph import WorkflowGraph
from comfy_local.selectors import SelectionError
from comfy_local.validation import ValidationError, validate_ui_graph


def node(node_id: int, node_type: str, key: str, *, inputs=None, outputs=None, widgets=None):
    return {
        "id": node_id,
        "type": node_type,
        "inputs": inputs or [],
        "outputs": outputs or [],
        "properties": {"studio_key": key, "studio_widgets": widgets or []},
        "widgets_values": [],
    }


def valid_workflow():
    return {
        "last_node_id": 2,
        "last_link_id": 1,
        "nodes": [
            node(1, "Source", "source", outputs=[{"name": "IMAGE", "type": "IMAGE", "links": [1]}]),
            node(
                2,
                "SaveImage",
                "save_image",
                inputs=[{"name": "images", "type": "IMAGE", "link": 1}],
                widgets=["filename_prefix"],
            ),
        ],
        "links": [[1, 1, 0, 2, 0, "IMAGE"]],
        "groups": [],
        "config": {},
        "extra": {
            "linearMode": True,
            "linearData": {
                "inputs": [[2, "filename_prefix"]],
                "outputs": [2],
            },
        },
        "version": 0.4,
    }


class SemanticSelectorTests(unittest.TestCase):
    def test_find_one_resolves_a_semantic_key(self) -> None:
        match = WorkflowGraph.from_ui_json(valid_workflow()).find_one(studio_key="save_image")
        self.assertEqual(2, match.id)
        self.assertEqual("2", match.app_id)

    def test_find_one_rejects_zero_matches(self) -> None:
        graph = WorkflowGraph.from_ui_json(valid_workflow())
        with self.assertRaisesRegex(SelectionError, "matched 0 nodes"):
            graph.find_one(studio_key="missing")

    def test_find_one_rejects_ambiguous_matches(self) -> None:
        workflow = valid_workflow()
        workflow["nodes"][0]["properties"]["studio_key"] = "save_image"
        graph = WorkflowGraph.from_ui_json(workflow)
        with self.assertRaisesRegex(SelectionError, "matched 2 nodes"):
            graph.find_one(studio_key="save_image")

    def test_subgraph_matches_use_a_composite_app_id(self) -> None:
        workflow = valid_workflow()
        workflow["definitions"] = {
            "subgraphs": [
                {
                    "id": "family-graph",
                    "last_node_id": 7,
                    "last_link_id": 0,
                    "nodes": [node(7, "PrimitiveInt", "width", widgets=["value"])],
                    "links": [],
                }
            ]
        }
        match = WorkflowGraph.from_ui_json(workflow).find_one(studio_key="width")
        self.assertEqual("family-graph:7", match.app_id)


class GraphValidationTests(unittest.TestCase):
    def assert_invalid(self, workflow, message: str) -> None:
        with self.assertRaisesRegex(ValidationError, message):
            validate_ui_graph(WorkflowGraph.from_ui_json(workflow))

    def test_valid_graph_passes(self) -> None:
        validate_ui_graph(WorkflowGraph.from_ui_json(valid_workflow()))

    def test_duplicate_semantic_keys_are_rejected(self) -> None:
        workflow = valid_workflow()
        workflow["nodes"][0]["properties"]["studio_key"] = "save_image"
        self.assert_invalid(workflow, "Duplicate studio_key")

    def test_duplicate_node_ids_are_rejected(self) -> None:
        workflow = valid_workflow()
        duplicate = deepcopy(workflow["nodes"][0])
        duplicate["properties"]["studio_key"] = "second_source"
        workflow["nodes"].append(duplicate)
        self.assert_invalid(workflow, "Duplicate node id")

    def test_duplicate_link_ids_are_rejected(self) -> None:
        workflow = valid_workflow()
        workflow["links"].append(deepcopy(workflow["links"][0]))
        self.assert_invalid(workflow, "Duplicate link id")

    def test_missing_link_source_is_rejected(self) -> None:
        workflow = valid_workflow()
        workflow["links"][0][1] = 99
        self.assert_invalid(workflow, "missing source node")

    def test_link_type_mismatch_is_rejected(self) -> None:
        workflow = valid_workflow()
        workflow["links"][0][5] = "MASK"
        self.assert_invalid(workflow, "source type IMAGE")

    def test_negative_link_socket_indexes_are_rejected(self) -> None:
        for index in (2, 4):
            with self.subTest(index=index):
                workflow = valid_workflow()
                workflow["links"][0][index] = -1
                self.assert_invalid(workflow, "invalid .* slot")

    def test_unknown_app_widget_is_rejected(self) -> None:
        workflow = valid_workflow()
        workflow["extra"]["linearData"]["inputs"][0][1] = "not_a_widget"
        self.assert_invalid(workflow, "unknown widget")

    def test_linear_data_requires_enabled_linear_mode(self) -> None:
        workflow = valid_workflow()
        workflow["extra"]["linearMode"] = False
        self.assert_invalid(workflow, "linearMode")

    def test_missing_app_output_is_rejected(self) -> None:
        workflow = valid_workflow()
        workflow["extra"]["linearData"]["outputs"] = [99]
        self.assert_invalid(workflow, "missing output node")

    def test_last_node_id_must_match_serialized_nodes(self) -> None:
        workflow = valid_workflow()
        workflow["last_node_id"] = 12
        self.assert_invalid(workflow, "last_node_id")

    def test_absolute_widget_paths_are_rejected(self) -> None:
        workflow = valid_workflow()
        workflow["nodes"][1]["widgets_values"] = [r"C:\private\model.safetensors"]
        self.assert_invalid(workflow, "absolute path")


if __name__ == "__main__":
    unittest.main()
