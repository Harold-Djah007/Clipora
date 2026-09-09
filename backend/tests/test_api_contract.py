from app.services.platforms import detect_platform


def test_detect_contract_for_threads_session_hint():
    info = detect_platform("https://www.threads.com/@creator/post/ABC123")
    assert info.platform.value == "threads"
    assert info.needs_local_session is True
    assert info.supports_server_resolve is True


def test_detect_contract_for_public_x_link():
    info = detect_platform("https://x.com/user/status/1234567890")
    assert info.platform.value == "x"
    assert info.needs_local_session is False
    assert info.supports_server_resolve is True
