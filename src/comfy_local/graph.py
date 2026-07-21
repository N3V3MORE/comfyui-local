from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Iterator


@dataclass(frozen=True)
class NodeRef:
    node: dict[str, Any]
    scope: str | None = None

    @property
    def id(self) -> Any:
        return self.node["id"]

    @property
    def app_id(self) -> str:
        return f"{self.scope}:{self.id}" if self.scope else str(self.id)

    @property
    def studio_key(self) -> str | None:
        properties = self.node.get("properties", {})
        return properties.get("studio_key") if isinstance(properties, dict) else None


class WorkflowGraph:
    def __init__(self, data: dict[str, Any]):
        self.data = data

    @classmethod
    def from_ui_json(cls, data: dict[str, Any]) -> "WorkflowGraph":
        if not isinstance(data, dict) or "nodes" not in data:
            raise ValueError("A UI workflow must contain a nodes collection")
        return cls(data)

    def scopes(self) -> Iterator[tuple[str | None, dict[str, Any]]]:
        yield None, self.data
        definitions = self.data.get("definitions", {})
        for subgraph in definitions.get("subgraphs", []) if isinstance(definitions, dict) else []:
            yield str(subgraph["id"]), subgraph

    def nodes(self) -> Iterator[NodeRef]:
        for scope, graph in self.scopes():
            for value in graph.get("nodes", []):
                yield NodeRef(value, scope)

    def find_one(
        self,
        *,
        studio_key: str | None = None,
        node_type: str | None = None,
        title: str | None = None,
    ) -> NodeRef:
        from .selectors import select_one

        return select_one(self.nodes(), studio_key=studio_key, node_type=node_type, title=title)

    def resolve_app_id(self, app_id: Any) -> NodeRef | None:
        text = str(app_id)
        for candidate in self.nodes():
            if candidate.app_id == text:
                return candidate
        return None
