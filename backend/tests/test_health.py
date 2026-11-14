from app.health import health


def test_health_returns_ok() -> None:
    """HEALTH-1

    アプリが応答できるかを、外から確かめる口として使うため。
    """
    assert health() == {"status": "ok"}
