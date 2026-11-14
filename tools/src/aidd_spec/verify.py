"""計画のテストケースと、テストから生成した仕様を照合する。

確かめること:
- 計画にある ID のテストがあるか(状態が「削除」なら、無いこと)
- テスト名が計画と一致するか
- 計画の表の列名がテストのパラメータ名と一致する列は、値が一致するか
列名がパラメータ名と一致しない列(「入力」「期待」など)は照合しない。人間と AI のレビューで確かめる。
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from aidd_spec.plan import PlannedCase
from aidd_spec.spec import SpecItem


@dataclass(frozen=True)
class Finding:
    case: PlannedCase
    ok: bool
    message: str


def _normalize_name(name: str) -> str:
    return re.sub(r"[\s_]", "", name.removeprefix("test_"))


def _normalize_value(value: str) -> str:
    return re.sub(r"[\s,_]", "", value)


def _check(case: PlannedCase, candidates: list[SpecItem]) -> Finding:
    label = f"{case.test_id} {case.name}".strip()
    if case.deleted:
        if candidates:
            return Finding(case, False, f"{case.test_id}: 計画では削除だが、テストが残っている")
        return Finding(case, True, f"{case.test_id}: 削除済み")
    if not candidates:
        return Finding(case, False, f"{case.test_id}: 計画にあるが、テストがない")

    matched = candidates
    if case.name:
        matched = [c for c in candidates if _normalize_name(c.name) == _normalize_name(case.name)]
        if not matched:
            names = "、".join(sorted({c.name for c in candidates}))
            return Finding(
                case,
                False,
                f"{case.test_id}: テスト名が違う(計画: {case.name} / テスト: {names})",
            )

    compared = {k: v for k, v in case.values.items() if k in matched[0].params}
    for item in matched:
        mismatches = [
            f"{k}={v}(テストでは {item.params[k]})"
            for k, v in compared.items()
            if _normalize_value(v) != _normalize_value(item.params[k])
        ]
        if not mismatches:
            return Finding(case, True, label)
    detail = "、".join(
        f"{k}={v}(テストでは {matched[0].params[k]})"
        for k, v in compared.items()
        if _normalize_value(v) != _normalize_value(matched[0].params[k])
    )
    return Finding(case, False, f"{case.test_id}: 値が違う。計画では {detail}")


def verify(cases: list[PlannedCase], items: list[SpecItem]) -> list[Finding]:
    by_id: dict[str, list[SpecItem]] = {}
    for item in items:
        if item.test_id is not None:
            by_id.setdefault(item.test_id, []).append(item)
    return [_check(case, by_id.get(case.test_id, [])) for case in cases]
