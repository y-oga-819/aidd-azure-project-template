"""テスト ID の重複と書き漏れを検出する。

テスト ID は計画・PR 概要・テストを結ぶ(docs/testing-strategy.md 5 章)。
連番で振るので、並行するブランチで同じ番号を取り合うことがある。git は別のファイルや別の位置に
足された同じ ID を黙ってマージし、計画の照合(verify)もテスト名で片方に一致させて通してしまう。
そのため重複はここで検出し、後からマージする側が振り直す。
"""

from __future__ import annotations

from dataclasses import dataclass

from aidd_spec.spec import SpecItem


@dataclass(frozen=True)
class Problem:
    kind: str  # "重複" | "ID なし"
    message: str


def _where(item: SpecItem) -> str:
    return f"{item.component}/{item.path}::{item.function}({item.name})"


def check(items: list[SpecItem]) -> list[Problem]:
    by_id: dict[str, list[SpecItem]] = {}
    for item in items:
        if item.test_id is not None:
            by_id.setdefault(item.test_id, []).append(item)

    problems = [
        Problem("重複", f"{test_id} が {len(found)} 件ある: " + "、".join(_where(i) for i in found))
        for test_id, found in sorted(by_id.items())
        if len(found) > 1
    ]
    problems += [
        Problem("ID なし", f"テスト ID がない: {_where(item)}")
        for item in items
        if item.test_id is None
    ]
    return problems
