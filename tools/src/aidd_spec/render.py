"""仕様一覧を Markdown にする。

形式は計画のテストケース一覧(docs/templates/plan.md 4 章)に揃える。
"""

from __future__ import annotations

from collections import defaultdict
from itertools import groupby

from aidd_spec.spec import SpecItem

_LAYER_ORDER = {"単体": 0, "統合": 1, "E2E": 2, "その他": 3}


def _cell(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", " ")


def _row(cells: list[str]) -> str:
    return "| " + " | ".join(_cell(c) for c in cells) + " |"


def _table(header: list[str], rows: list[list[str]]) -> list[str]:
    return [_row(header), "|" + "---|" * len(header), *(_row(r) for r in rows)]


def _id(item: SpecItem) -> str:
    return item.test_id or "(ID なし)"


def render_markdown(items: list[SpecItem]) -> str:
    lines = ["# 仕様一覧(テストから生成)", ""]
    missing = [i for i in items if i.test_id is None]
    lines += [f"テスト {len(items)} 件 / ID なし {len(missing)} 件", ""]

    by_component: dict[str, list[SpecItem]] = defaultdict(list)
    for item in items:
        by_component[item.component].append(item)

    for component, component_items in sorted(by_component.items()):
        lines += [f"## {component}", ""]
        ordered = sorted(component_items, key=lambda i: (_LAYER_ORDER[i.layer], i.path))
        for (layer, path), file_items_iter in groupby(ordered, key=lambda i: (i.layer, i.path)):
            file_items = list(file_items_iter)
            lines += [f"### {layer}: {path}", ""]
            plain = [i for i in file_items if not i.params]
            if plain:
                lines += _table(["ID", "テスト名", "why"], [[_id(i), i.name, i.why] for i in plain])
                lines.append("")
            parametrized = [i for i in file_items if i.params]
            for group, group_iter in groupby(parametrized, key=lambda i: i.group):
                group_items = list(group_iter)
                lines += [f"#### {group}", ""]
                if group_items[0].why:
                    lines += [f"why: {group_items[0].why}", ""]
                keys = list(group_items[0].params)
                lines += _table(
                    ["ID", "テスト名", *keys],
                    [[_id(i), i.name, *(i.params.get(k, "") for k in keys)] for i in group_items],
                )
                lines.append("")
    return "\n".join(lines).rstrip() + "\n"
