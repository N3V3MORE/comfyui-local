from __future__ import annotations

import json
from copy import deepcopy
from pathlib import Path, PurePosixPath, PureWindowsPath
from typing import Any, Iterator


class ApiPromptError(ValueError):
    pass


class ApiPromptGraph:
    def __init__(self, data: dict[str, dict[str, Any]]):
        self.data = data

    @classmethod
    def load(cls, path: Path) -> "ApiPromptGraph":
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise ApiPromptError(f"Could not load API prompt template {path}: {error}") from error
        return cls(value)

    def copy(self) -> "ApiPromptGraph":
        return ApiPromptGraph(deepcopy(self.data))

    def find_one(self, studio_key: str) -> dict[str, Any]:
        matches = [
            node
            for node in self.data.values()
            if node.get("_meta", {}).get("studio_key") == studio_key
        ]
        if len(matches) != 1:
            raise ApiPromptError(
                f"API selector studio_key={studio_key!r} matched {len(matches)} nodes; expected exactly one"
            )
        return matches[0]

    def set_input(self, studio_key: str, name: str, value: Any) -> None:
        node = self.find_one(studio_key)
        if name not in node.get("inputs", {}):
            raise ApiPromptError(f"API node {studio_key!r} has no input {name!r}")
        node["inputs"][name] = value

    def validate(self) -> None:
        keys: set[str] = set()
        for node_id, node in self.data.items():
            key = node.get("_meta", {}).get("studio_key")
            if not key:
                raise ApiPromptError(f"API node {node_id} has no studio_key")
            if key in keys:
                raise ApiPromptError(f"Duplicate API studio_key: {key}")
            keys.add(key)
            for value in node.get("inputs", {}).values():
                if isinstance(value, list) and len(value) == 2 and isinstance(value[1], int):
                    if str(value[0]) not in self.data:
                        raise ApiPromptError(f"API node {node_id} references missing node {value[0]}")
                for text in _strings(value):
                    if "://" not in text and (
                        PureWindowsPath(text).is_absolute() or PurePosixPath(text).is_absolute()
                    ):
                        raise ApiPromptError(f"API node {node_id} contains an absolute path: {text}")


def _strings(value: Any) -> Iterator[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from _strings(item)
    elif isinstance(value, (list, tuple)):
        for item in value:
            yield from _strings(item)
