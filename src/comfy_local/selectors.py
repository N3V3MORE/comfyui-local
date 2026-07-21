from __future__ import annotations

from collections.abc import Iterable

from .graph import NodeRef


class SelectionError(ValueError):
    pass


def select_one(
    nodes: Iterable[NodeRef],
    *,
    studio_key: str | None = None,
    node_type: str | None = None,
    title: str | None = None,
) -> NodeRef:
    criteria = {
        "studio_key": studio_key,
        "node_type": node_type,
        "title": title,
    }
    active = {name: value for name, value in criteria.items() if value is not None}
    if not active:
        raise SelectionError("A selector requires studio_key, node_type, or title")

    matches = [node for node in nodes if _matches(node, studio_key, node_type, title)]
    if len(matches) != 1:
        rendered = ", ".join(f"{name}={value!r}" for name, value in active.items())
        raise SelectionError(f"Selector {rendered} matched {len(matches)} nodes; expected exactly one")
    return matches[0]


def _matches(node: NodeRef, studio_key: str | None, node_type: str | None, title: str | None) -> bool:
    return (
        (studio_key is None or node.studio_key == studio_key)
        and (node_type is None or node.node.get("type") == node_type)
        and (title is None or node.node.get("title") == title)
    )
