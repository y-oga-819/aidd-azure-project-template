"""死活監視用のエンドポイントが返す内容。フレームワーク選定前の動作確認用。"""

from typing import TypedDict


class HealthStatus(TypedDict):
    status: str


def health() -> HealthStatus:
    return {"status": "ok"}
