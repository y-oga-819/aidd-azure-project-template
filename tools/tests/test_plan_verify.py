import pytest

from aidd_spec.plan import parse
from aidd_spec.spec import SpecItem
from aidd_spec.verify import verify

PLAN = """\
# 計画: 送料

## 2. テストケースの洗い出し

| ID | テスト名 | 地域 |
|---|---|---|
| SHIPPING-9 | ここは一覧の外なので読まない | 本州等 |

## 4. テストケース一覧

### 単体: pricing/shipping

網羅の軸: 地域 2 × ランク 2

| ID | テスト名 | 地域 | 小計 | 期待する送料 | 状態 |
|---|---|---|---|---|---|
| SHIPPING-1 | 本州等は閾値以上なら無料 | 本州等 | 5,000 | 0 | 既存 |
| SHIPPING-3 | 本州等のゴールド会員は閾値未満でも無料 | 本州等 | 4,999 | 0 | 新規 |
| SHIPPING-7 | 旧ルール | - | | | 削除 |

### 統合: checkout

| ID | テスト名 | 状態 |
|---|---|---|
| PAYMENT-1 | 注文確定のハッピーパス | 既存 |

## 5. PR の分割

| PR | 中身 | テスト ID | 依存 |
|---|---|---|---|
| A | 送料 | SHIPPING-3 | なし |
"""


def _item(test_id: str, name: str, **params: str) -> SpecItem:
    return SpecItem(
        component="backend",
        path="tests/unit/test_shipping.py",
        function="test_x",
        test_id=test_id,
        name=name,
        group="x",
        layer="単体",
        why="",
        params=params,
    )


def test_テストケース一覧の節にあるid列の表だけを読む() -> None:
    """PLAN-VERIFY-1"""
    cases = parse(PLAN)

    assert [(c.test_id, c.state) for c in cases] == [
        ("SHIPPING-1", "既存"),
        ("SHIPPING-3", "新規"),
        ("SHIPPING-7", "削除"),
        ("PAYMENT-1", "既存"),
    ]


def test_計画の値の列は空欄とハイフンを除いて読む() -> None:
    """PLAN-VERIFY-2"""
    cases = parse(PLAN)

    assert (cases[0].values, cases[2].values) == (
        {"地域": "本州等", "小計": "5,000", "期待する送料": "0"},
        {},
    )


def test_計画とテストが一致すれば全件一致になる() -> None:
    """PLAN-VERIFY-3"""
    items = [
        _item(
            "SHIPPING-1", "本州等は閾値以上なら無料", 地域="本州等", 小計="5000", 期待する送料="0"
        ),
        _item("SHIPPING-3", "本州等のゴールド会員は閾値未満でも無料", 地域="本州等", 小計="4999"),
        _item("PAYMENT-1", "注文確定のハッピーパス"),
    ]

    assert [f.ok for f in verify(parse(PLAN), items)] == [True, True, True, True]


@pytest.mark.parametrize(
    ("テスト", "期待するメッセージ"),
    [
        pytest.param(
            [],
            "SHIPPING-1: 計画にあるが、テストがない",
            id="PLAN-VERIFY-4 テストがない",
        ),
        pytest.param(
            [_item("SHIPPING-1", "閾値以上は無料", 小計="5000")],
            "SHIPPING-1: テスト名が違う(計画: 本州等は閾値以上なら無料 / テスト: 閾値以上は無料)",
            id="PLAN-VERIFY-4 テスト名が違う",
        ),
        pytest.param(
            [_item("SHIPPING-1", "本州等は閾値以上なら無料", 小計="4999")],
            "SHIPPING-1: 値が違う。計画では 小計=5,000(テストでは 4999)",
            id="PLAN-VERIFY-4 パラメータの値が違う",
        ),
    ],
)
def test_計画とテストが食い違えば理由を示して不一致にする(
    テスト: list[SpecItem], 期待するメッセージ: str
) -> None:
    first = verify(parse(PLAN), テスト)[0]

    assert (first.ok, first.message) == (False, 期待するメッセージ)


def test_計画で削除のテストが残っていれば不一致にする() -> None:
    """PLAN-VERIFY-5"""
    findings = verify(parse(PLAN), [_item("SHIPPING-7", "旧ルール")])

    assert (findings[2].ok, findings[2].message) == (
        False,
        "SHIPPING-7: 計画では削除だが、テストが残っている",
    )


def test_テスト名の空白とアンダースコアの違いは同じ名前とみなす() -> None:
    """PLAN-VERIFY-6"""
    items = [_item("SHIPPING-1", "本州等は 閾値以上なら_無料", 小計="5000")]

    assert verify(parse(PLAN), items)[0].ok
