import json
from pathlib import Path

import pytest

from aidd_spec.render import render_markdown
from aidd_spec.spec import load

SAMPLE_TEST = '''
import enum
import pytest

class Region(enum.Enum):
    本州等 = "honshu"

@pytest.mark.parametrize(
    ("地域", "小計", "期待する送料"),
    [pytest.param(Region.本州等, 5_000, 0, id="SHIPPING-1 本州等は閾値以上なら無料")],
)
def test_基本送料は地域と小計で決まる(地域, 小計, 期待する送料):
    """SHIPPING-1〜2
    ゴールド会員の継続率を上げるため。
    """

def test_抽選待ちで当選すると確定になる():
    """ORDER-8"""
'''


def test_収集結果をjsonに書き出しテストは実行しない(
    pytester: pytest.Pytester, monkeypatch: pytest.MonkeyPatch
) -> None:
    """DOCS-SPEC-7"""
    pytester.makepyfile(**{"tests/unit/test_shipping": SAMPLE_TEST})
    out = pytester.path / "collected.json"
    monkeypatch.setenv("AIDD_SPEC_OUT", str(out))
    monkeypatch.setenv("AIDD_SPEC_COMPONENT", "backend")

    result = pytester.runpytest("--collect-only", "-q", "-p", "aidd_spec.pytest_plugin")

    result.assert_outcomes()
    payload = json.loads(out.read_text(encoding="utf-8"))
    assert (payload["component"], [i["params"] for i in payload["items"]]) == (
        "backend",
        [{"地域": "本州等", "小計": "5000", "期待する送料": "0"}, {}],
    )


def test_収集結果から層とファイルとテストごとの仕様一覧を作る(
    pytester: pytest.Pytester, monkeypatch: pytest.MonkeyPatch
) -> None:
    """DOCS-SPEC-8"""
    pytester.makepyfile(**{"tests/unit/test_shipping": SAMPLE_TEST})
    out = pytester.path / "collected.json"
    monkeypatch.setenv("AIDD_SPEC_OUT", str(out))
    monkeypatch.setenv("AIDD_SPEC_COMPONENT", "backend")
    pytester.runpytest("--collect-only", "-q", "-p", "aidd_spec.pytest_plugin")

    markdown = render_markdown(load([Path(out)]))

    assert markdown == (
        "# 仕様一覧(テストから生成)\n"
        "\n"
        "テスト 2 件 / ID なし 0 件\n"
        "\n"
        "## backend\n"
        "\n"
        "### 単体: tests/unit/test_shipping.py\n"
        "\n"
        "| ID | テスト名 | why |\n"
        "|---|---|---|\n"
        "| ORDER-8 | 抽選待ちで当選すると確定になる |  |\n"
        "\n"
        "#### 基本送料は地域と小計で決まる\n"
        "\n"
        "why: ゴールド会員の継続率を上げるため。\n"
        "\n"
        "| ID | テスト名 | 地域 | 小計 | 期待する送料 |\n"
        "|---|---|---|---|---|\n"
        "| SHIPPING-1 | 本州等は閾値以上なら無料 | 本州等 | 5000 | 0 |\n"
    )
