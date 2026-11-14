"""pytest のテスト収集結果を JSON に書き出すプラグイン。

使い方: AIDD_SPEC_OUT=<出力先> pytest --collect-only -q -p aidd_spec.pytest_plugin
テストは実行しない。解釈(ID の取り出しなど)は aidd_spec.spec が行い、ここでは生の情報だけを集める。
"""

from __future__ import annotations

import enum
import inspect
import json
import os
from pathlib import Path
from typing import Any

import pytest


def _format_value(value: object) -> str:
    if isinstance(value, enum.Enum):
        return value.name
    if isinstance(value, str):
        return value
    return repr(value)


def _unescape(param_id: str) -> str:
    """pytest が ASCII にエスケープした id(\\uXXXX)を元に戻す。

    pytest は既定で id の非 ASCII 文字をエスケープする(str.encode("unicode_escape"))。
    エスケープを止める設定をしている場合は非 ASCII のまま届くので、そのまま返す。
    """
    try:
        return param_id.encode("ascii").decode("unicode_escape")
    except UnicodeError:
        return param_id


def _collect(item: pytest.Item, rootdir: Path) -> dict[str, Any]:
    function = getattr(item, "function", None)
    callspec = getattr(item, "callspec", None)
    return {
        "nodeid": item.nodeid,
        "path": Path(str(item.path)).relative_to(rootdir).as_posix(),
        "function": getattr(item, "originalname", item.name),
        "doc": (inspect.getdoc(function) or "") if function is not None else "",
        "param_id": _unescape(callspec.id) if callspec is not None else None,
        "params": (
            {key: _format_value(value) for key, value in callspec.params.items()}
            if callspec is not None
            else {}
        ),
    }


def pytest_collection_finish(session: pytest.Session) -> None:
    out = os.environ.get("AIDD_SPEC_OUT")
    if not out:
        return
    rootdir = Path(str(session.config.rootpath))
    payload = {
        "component": os.environ.get("AIDD_SPEC_COMPONENT", rootdir.name),
        "items": [_collect(item, rootdir) for item in session.items],
    }
    Path(out).write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
