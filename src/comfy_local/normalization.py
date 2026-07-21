from __future__ import annotations

from copy import deepcopy
from typing import Any


def normalize_workflow(value: Any) -> Any:
    """Remove presentation-only fields while retaining executable semantics."""
    normalized = deepcopy(value)
    if not isinstance(normalized, dict) or "nodes" not in normalized:
        return normalized

    _normalize_ui_graph(normalized)
    return normalized


def _normalize_ui_graph(graph: dict[str, Any]) -> None:
    graph.pop("groups", None)
    extra = graph.get("extra")
    if isinstance(extra, dict):
        extra.pop("ds", None)

    nodes = graph.get("nodes", [])
    for node in nodes:
        node.pop("pos", None)
        node.pop("size", None)
    graph["nodes"] = sorted(nodes, key=lambda node: str(node.get("id", "")))

    links = graph.get("links", [])
    graph["links"] = sorted(links, key=_link_key)

    definitions = graph.get("definitions", {})
    subgraphs = definitions.get("subgraphs", []) if isinstance(definitions, dict) else []
    for subgraph in subgraphs:
        _normalize_ui_graph(subgraph)
    if subgraphs:
        definitions["subgraphs"] = sorted(subgraphs, key=lambda item: str(item.get("id", "")))


def _link_key(link: Any) -> str:
    if isinstance(link, dict):
        return str(link.get("id", ""))
    if isinstance(link, list) and link:
        return str(link[0])
    return ""
