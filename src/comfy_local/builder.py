from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


class GraphBuilderError(ValueError):
    pass


@dataclass(frozen=True)
class OutputHandle:
    node_key: str
    name: str
    type: str


@dataclass
class NodeHandle:
    _builder: "GraphBuilder"
    key: str
    node_type: str
    inputs: dict[str, OutputHandle] = field(default_factory=dict)
    input_types: dict[str, str] = field(default_factory=dict)
    output_types: dict[str, str] = field(default_factory=dict)
    widgets: dict[str, Any] = field(default_factory=dict)
    title: str | None = None

    def output(self, name: str) -> OutputHandle:
        if name not in self.output_types:
            raise GraphBuilderError(f"Unknown output {name!r} on node {self.key!r}")
        return OutputHandle(self.key, name, self.output_types[name])


class GraphBuilder:
    def __init__(self) -> None:
        self._nodes: list[NodeHandle] = []
        self._keys: set[str] = set()

    def add(
        self,
        node_type: str,
        *,
        key: str,
        inputs: dict[str, OutputHandle] | None = None,
        input_types: dict[str, str] | None = None,
        outputs: dict[str, str] | None = None,
        widgets: dict[str, Any] | None = None,
        title: str | None = None,
    ) -> NodeHandle:
        if key in self._keys:
            raise GraphBuilderError(f"Duplicate node key: {key}")
        self._keys.add(key)
        handle = NodeHandle(
            _builder=self,
            key=key,
            node_type=node_type,
            inputs=dict(inputs or {}),
            input_types=dict(input_types or {}),
            output_types=dict(outputs or {}),
            widgets=dict(widgets or {}),
            title=title,
        )
        for input_name, output in handle.inputs.items():
            if input_name not in handle.input_types:
                raise GraphBuilderError(f"Missing input type for {key}.{input_name}")
            if output.node_key not in self._keys:
                raise GraphBuilderError(f"Input {key}.{input_name} references an unknown node")
        self._nodes.append(handle)
        return handle

    def to_ui_workflow(
        self,
        *,
        app_inputs: list[tuple[NodeHandle, str]] | None = None,
        app_outputs: list[NodeHandle] | None = None,
    ) -> dict[str, Any]:
        node_ids = {node.key: index for index, node in enumerate(self._nodes, start=1)}
        link_id = 0
        links: list[list[Any]] = []
        output_links: dict[tuple[str, str], list[int]] = {}
        input_links: dict[tuple[str, str], int] = {}

        for target in self._nodes:
            for target_slot, (input_name, source) in enumerate(target.inputs.items()):
                link_id += 1
                source_node = self._node(source.node_key)
                source_slot = list(source_node.output_types).index(source.name)
                link_type = source.type
                expected_type = target.input_types[input_name]
                if expected_type not in {"*", link_type}:
                    raise GraphBuilderError(
                        f"Type mismatch for {target.key}.{input_name}: {link_type} -> {expected_type}"
                    )
                links.append(
                    [link_id, node_ids[source.node_key], source_slot, node_ids[target.key], target_slot, link_type]
                )
                output_links.setdefault((source.node_key, source.name), []).append(link_id)
                input_links[(target.key, input_name)] = link_id

        serialized_nodes = []
        for order, node in enumerate(self._nodes):
            inputs = [
                {
                    "name": name,
                    "type": node.input_types[name],
                    "link": input_links[(node.key, name)],
                }
                for name in node.inputs
            ]
            outputs = [
                {
                    "name": name,
                    "type": output_type,
                    "links": output_links.get((node.key, name)) or None,
                    "slot_index": slot,
                }
                for slot, (name, output_type) in enumerate(node.output_types.items())
            ]
            value: dict[str, Any] = {
                "id": node_ids[node.key],
                "type": node.node_type,
                "pos": [order * 350, 0],
                "size": [315, 100],
                "flags": {},
                "order": order,
                "mode": 0,
                "inputs": inputs,
                "outputs": outputs,
                "properties": {
                    "studio_key": node.key,
                    "studio_widgets": list(node.widgets),
                },
                "widgets_values": list(node.widgets.values()),
            }
            if node.title:
                value["title"] = node.title
            serialized_nodes.append(value)

        linear_inputs = [
            [node_ids[node.key], widget]
            for node, widget in app_inputs or []
        ]
        linear_outputs = [node_ids[node.key] for node in app_outputs or []]
        return {
            "last_node_id": len(serialized_nodes),
            "last_link_id": link_id,
            "nodes": serialized_nodes,
            "links": links,
            "groups": [],
            "config": {},
            "extra": {
                "linearMode": bool(linear_inputs or linear_outputs),
                "linearData": {"inputs": linear_inputs, "outputs": linear_outputs},
            },
            "version": 0.4,
        }

    def _node(self, key: str) -> NodeHandle:
        for node in self._nodes:
            if node.key == key:
                return node
        raise GraphBuilderError(f"Unknown node key: {key}")
