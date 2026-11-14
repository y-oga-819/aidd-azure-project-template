import pytest

from aidd_spec.spec import filter_items, to_item


def _raw(**overrides: object) -> dict[str, object]:
    raw: dict[str, object] = {
        "path": "tests/unit/test_x.py",
        "function": "test_何かができる",
        "doc": "",
        "param_id": None,
        "params": {},
    }
    raw.update(overrides)
    return raw


def test_パラメータのidの先頭からテストidとテスト名を取り出す() -> None:
    """DOCS-SPEC-1"""
    item = to_item(
        "backend",
        _raw(param_id="SHIPPING-2 本州等の一般会員は閾値未満なら600円", params={"小計": "4999"}),
    )

    assert (item.test_id, item.name) == ("SHIPPING-2", "本州等の一般会員は閾値未満なら600円")


def test_パラメータ化していないテストはdocstringの1行目をテストidにする() -> None:
    """DOCS-SPEC-2"""
    item = to_item("backend", _raw(doc="ORDER-3\n\n倉庫がピッキング済みの場合があるため。"))

    assert (item.test_id, item.name, item.why) == (
        "ORDER-3",
        "何かができる",
        "倉庫がピッキング済みの場合があるため。",
    )


def test_docstringの1行目がidでなければ全体をwhyとして扱いidはなし() -> None:
    """DOCS-SPEC-3"""
    item = to_item("backend", _raw(doc="理由だけを書いた。"))

    assert (item.test_id, item.why) == (None, "理由だけを書いた。")


def test_パラメータ化テストのdocstringの1行目のid範囲は読み飛ばしてwhyだけを取る() -> None:
    """DOCS-SPEC-4"""
    item = to_item(
        "backend",
        _raw(
            doc="SHIPPING-1〜3\n継続率を上げるため。", param_id="SHIPPING-1 無料", params={"a": "1"}
        ),
    )

    assert (item.test_id, item.why) == ("SHIPPING-1", "継続率を上げるため。")


@pytest.mark.parametrize(
    ("パス", "層"),
    [
        pytest.param("tests/unit/domain/test_a.py", "単体", id="DOCS-SPEC-5 unit は単体"),
        pytest.param("tests/integration/test_a.py", "統合", id="DOCS-SPEC-5 integration は統合"),
        pytest.param("e2e/test_a.py", "E2E", id="DOCS-SPEC-5 e2e は E2E"),
        pytest.param("tests/test_a.py", "その他", id="DOCS-SPEC-5 どれでもなければその他"),
    ],
)
def test_テストの層はパスのディレクトリ名で決まる(パス: str, 層: str) -> None:
    assert to_item("backend", _raw(path=パス)).layer == 層


@pytest.mark.parametrize(
    "パラメータのid",
    [
        pytest.param("ORD1 略語", id="DOCS-SPEC-6 ハイフンがない"),
        pytest.param("order-1 小文字", id="DOCS-SPEC-6 小文字"),
        pytest.param("本州等 4999", id="DOCS-SPEC-6 ID がない"),
    ],
)
def test_id形式でないパラメータのidはテスト名として扱いidはなし(パラメータのid: str) -> None:
    item = to_item("backend", _raw(param_id=パラメータのid, params={"a": "1"}))

    assert (item.test_id, item.name) == (None, パラメータのid)


def test_絞り込みはテストのパスかテストidに文字列を含むものだけを残す() -> None:
    """DOCS-SPEC-9"""
    items = [
        to_item("backend", _raw(path="tests/unit/pricing/test_a.py")),
        to_item("backend", _raw(doc="SHIPPING-1")),
        to_item("backend", _raw(path="tests/unit/order/test_b.py", doc="ORDER-1")),
    ]

    assert [i.path for i in filter_items(items, "pricing")] + [
        i.test_id for i in filter_items(items, "SHIPPING")
    ] == ["tests/unit/pricing/test_a.py", "SHIPPING-1"]
