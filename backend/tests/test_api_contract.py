from app.services.platforms import detect_platform
from app.main import root


def test_detect_contract_for_public_threads_link():
    info = detect_platform("https://www.threads.com/@creator/post/ABC123")
    assert info.platform.value == "threads"
    assert info.needs_local_session is False
    assert info.supports_server_resolve is True


def test_detect_contract_for_public_x_link():
    info = detect_platform("https://x.com/user/status/1234567890")
    assert info.platform.value == "x"
    assert info.needs_local_session is False
    assert info.supports_server_resolve is True


def test_service_root_is_a_useful_deployment_status_page():
    assert root() == {
        "ok": True,
        "service": "clipora",
        "version": "2.0.10",
        "health": "/health",
        "docs": "/docs",
        "platform_session": {
            "cookies_configured": False,
            "proxy_configured": False,
        },
    }
