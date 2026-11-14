"""収集結果を仕様の行(SpecItem)に解釈する。

テスト ID の書き方(docs/testing-strategy.md 5 章):
- パラメータ化テスト: pytest.param(..., id="SHIPPING-2 本州等の一般会員は閾値未満なら600円")
- それ以外: docstring の 1 行目に ID だけを書く
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

# 接頭辞は機能の正式名(大文字、ハイフン区切り可)+ 連番。例: ORDER-1, SHIPPING-12, GIFT-CARD-3
ID_PATTERN = re.compile(r"^(?P<id>[A-Z][A-Z0-9]*(?:-[A-Z][A-Z0-9]*)*-\d+)(?:\s+(?P<rest>.*))?$")

LAYERS = {"unit": "単体", "integration": "統合", "e2e": "E2E"}


@dataclass(frozen=True)
class SpecItem:
    component: str
    path: str
    function: str
    test_id: str | None
    name: str
    group: str
    layer: str
    why: str
    params: dict[str, str] = field(default_factory=dict)


def _readable(function: str) -> str:
    name = function.removeprefix("test_")
    return name.replace("_", " ").strip()


def _layer(path: str) -> str:
    for part in Path(path).parts:
        if part in LAYERS:
            return LAYERS[part]
    return "その他"


# docstring の 1 行目が ID(または「SHIPPING-1〜3」のような ID の範囲)で始まるか
_ID_LINE = re.compile(r"^[A-Z][A-Z0-9]*(?:-[A-Z][A-Z0-9]*)*-\d")


def _split_doc(doc: str) -> tuple[str | None, str]:
    """docstring を (ID 行, why) に分ける。1 行目が ID でなければ全体が why。"""
    lines = [line.strip() for line in doc.strip().splitlines()]
    if not lines or not lines[0]:
        return None, ""
    if _ID_LINE.match(lines[0]):
        return lines[0], " ".join(line for line in lines[1:] if line)
    return None, " ".join(line for line in lines if line)


def to_item(component: str, raw: dict[str, Any]) -> SpecItem:
    function: str = raw["function"]
    group = _readable(function)
    id_line, why = _split_doc(raw.get("doc", ""))
    param_id: str | None = raw.get("param_id")

    test_id: str | None = None
    name = group
    if param_id is not None:
        match = ID_PATTERN.match(param_id)
        if match:
            test_id = match["id"]
            name = (match["rest"] or "").strip() or group
        else:
            name = param_id
    elif id_line is not None:
        match = ID_PATTERN.match(id_line)
        if match and not match["rest"]:
            test_id = match["id"]

    return SpecItem(
        component=component,
        path=raw["path"],
        function=function,
        test_id=test_id,
        name=name,
        group=group,
        layer=_layer(raw["path"]),
        why=why,
        params=dict(raw.get("params", {})),
    )


def load(paths: list[Path]) -> list[SpecItem]:
    items: list[SpecItem] = []
    for path in paths:
        payload = json.loads(path.read_text(encoding="utf-8"))
        component = payload["component"]
        items.extend(to_item(component, raw) for raw in payload["items"])
    return items


def filter_items(items: list[SpecItem], keyword: str) -> list[SpecItem]:
    """テストのパスかテスト ID に keyword を含むものだけを返す。空なら全部。"""
    if not keyword:
        return items
    return [i for i in items if keyword in i.path or keyword in (i.test_id or "")]
