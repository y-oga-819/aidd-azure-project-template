from aidd_spec.ids import check
from aidd_spec.spec import SpecItem


def _item(test_id: str | None, path: str = "tests/unit/test_order.py", name: str = "x") -> SpecItem:
    return SpecItem(
        component="backend",
        path=path,
        function="test_x",
        test_id=test_id,
        name=name,
        group="x",
        layer="単体",
        why="",
    )


def test_別のファイルにある同じidを重複として場所と一緒に挙げる() -> None:
    """TEST-IDS-1

    並行するブランチが同じ番号を別のファイルに足すと、git は黙ってマージする。
    照合も通ってしまうので、ここで止める。
    """
    problems = check(
        [
            _item("ORDER-9", "tests/unit/test_order_cancel.py", "キャンセルできる"),
            _item("ORDER-9", "tests/unit/test_order_lottery.py", "抽選待ちになる"),
            _item("ORDER-8"),
        ]
    )

    assert [p.kind for p in problems] == ["重複"]
    assert "ORDER-9 が 2 件" in problems[0].message
    assert "test_order_cancel.py" in problems[0].message
    assert "test_order_lottery.py" in problems[0].message


def test_idのないテストを書き漏れとして挙げる() -> None:
    """TEST-IDS-2

    ID のないテストは計画と PR から指せず、なぜ要るのかを辿れない。
    """
    problems = check([_item("ORDER-1"), _item(None, name="何かができる")])

    assert [p.kind for p in problems] == ["ID なし"]
    assert "何かができる" in problems[0].message


def test_idが揃っていれば問題はない() -> None:
    """TEST-IDS-3"""
    assert check([_item("ORDER-1"), _item("ORDER-2"), _item("SHIPPING-1")]) == []
