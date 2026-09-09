from app.services.safety import SAFE_RESOLVER_RULES


def test_safe_resolver_rules_are_recorded():
    joined = " ".join(SAFE_RESOLVER_RULES).lower()
    assert "passwords" in joined
    assert "private access" in joined
    assert "watermark-removal" in joined
