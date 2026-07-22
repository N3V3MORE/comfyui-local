from __future__ import annotations

from pathlib import PurePosixPath, PureWindowsPath
from typing import Any, Iterator

from .graph import NodeRef, WorkflowGraph


class ValidationError(ValueError):
    pass


def validate_ui_graph(workflow: WorkflowGraph) -> None:
    _validate_unique_keys(workflow)
    for scope, graph in workflow.scopes():
        _validate_scope(scope, graph)
    _validate_app_mode(workflow)
    _validate_paths(workflow)


def _validate_unique_keys(workflow: WorkflowGraph) -> None:
    seen: dict[str, NodeRef] = {}
    for node in workflow.nodes():
        key = node.studio_key
        if not key:
            continue
        if key in seen:
            raise ValidationError(f"Duplicate studio_key {key!r}: {seen[key].app_id} and {node.app_id}")
        seen[key] = node


def _validate_scope(scope: str | None, graph: dict[str, Any]) -> None:
    label = f"subgraph {scope}" if scope else "root graph"
    serialized_nodes = graph.get("nodes", [])
    nodes = {node["id"]: node for node in serialized_nodes}
    if len(nodes) != len(serialized_nodes):
        raise ValidationError(f"{label} has a Duplicate node id")
    links = graph.get("links", [])

    numeric_node_ids = [value for value in nodes if isinstance(value, int)]
    expected_last_node = max(numeric_node_ids, default=0)
    if graph.get("last_node_id", expected_last_node) != expected_last_node:
        raise ValidationError(f"{label} last_node_id does not match generated nodes")

    link_ids = [_link_parts(link)[0] for link in links]
    if len(link_ids) != len(set(link_ids)):
        raise ValidationError(f"{label} has a Duplicate link id")
    numeric_link_ids = [value for value in link_ids if isinstance(value, int)]
    expected_last_link = max(numeric_link_ids, default=0)
    if graph.get("last_link_id", expected_last_link) != expected_last_link:
        raise ValidationError(f"{label} last_link_id does not match generated links")

    for link in links:
        link_id, source_id, source_slot, target_id, target_slot, link_type = _link_parts(link)
        if source_id not in nodes and source_id != -10:
            raise ValidationError(f"{label} link {link_id} has a missing source node {source_id}")
        if target_id not in nodes and target_id != -20:
            raise ValidationError(f"{label} link {link_id} has a missing destination node {target_id}")

        source_outputs = graph.get("inputs", []) if source_id == -10 else nodes[source_id].get("outputs", [])
        target_inputs = graph.get("outputs", []) if target_id == -20 else nodes[target_id].get("inputs", [])
        if source_slot < 0 or source_slot >= len(source_outputs):
            raise ValidationError(f"{label} link {link_id} has an invalid source slot")
        if target_slot < 0 or target_slot >= len(target_inputs):
            raise ValidationError(f"{label} link {link_id} has an invalid destination slot")

        source_type = source_outputs[source_slot].get("type")
        target_type = target_inputs[target_slot].get("type")
        if link_type != "*" and source_type not in (None, "*", link_type):
            raise ValidationError(f"{label} link {link_id} type {link_type} does not match source type {source_type}")
        if link_type != "*" and target_type not in (None, "*", link_type):
            raise ValidationError(f"{label} link {link_id} type {link_type} does not match destination type {target_type}")


def _link_parts(link: Any) -> tuple[Any, Any, int, Any, int, Any]:
    if isinstance(link, dict):
        return (
            link.get("id"),
            link.get("origin_id"),
            int(link.get("origin_slot", 0)),
            link.get("target_id"),
            int(link.get("target_slot", 0)),
            link.get("type"),
        )
    if isinstance(link, list) and len(link) >= 6:
        return link[0], link[1], int(link[2]), link[3], int(link[4]), link[5]
    raise ValidationError(f"Malformed workflow link: {link!r}")


def _validate_app_mode(workflow: WorkflowGraph) -> None:
    extra = workflow.data.get("extra", {})
    if not isinstance(extra, dict):
        return
    linear = extra.get("linearData")
    linear_mode = extra.get("linearMode")
    if linear is None and linear_mode is None:
        return
    if linear_mode is not True or not isinstance(linear, dict):
        raise ValidationError("App Mode linearData requires linearMode=true")

    for value in linear.get("inputs", []):
        if not isinstance(value, list) or len(value) != 2:
            raise ValidationError(f"Malformed App Mode input: {value!r}")
        node = workflow.resolve_app_id(value[0])
        if node is None:
            raise ValidationError(f"App Mode input references missing node {value[0]}")
        properties = node.node.get("properties", {})
        widgets = properties.get("studio_widgets", []) if isinstance(properties, dict) else []
        if value[1] not in widgets:
            raise ValidationError(f"App Mode input {node.app_id} references unknown widget {value[1]!r}")

    root_ids = {str(node["id"]) for node in workflow.data.get("nodes", [])}
    for output_id in linear.get("outputs", []):
        if str(output_id) not in root_ids:
            raise ValidationError(f"App Mode references missing output node {output_id}")


def _validate_paths(workflow: WorkflowGraph) -> None:
    for node in workflow.nodes():
        for value in _strings(node.node.get("widgets_values", [])):
            if "://" in value:
                continue
            if PureWindowsPath(value).is_absolute() or PurePosixPath(value).is_absolute():
                raise ValidationError(f"Node {node.app_id} contains an unapproved absolute path: {value}")


def _strings(value: Any) -> Iterator[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from _strings(item)
    elif isinstance(value, (list, tuple)):
        for item in value:
            yield from _strings(item)
