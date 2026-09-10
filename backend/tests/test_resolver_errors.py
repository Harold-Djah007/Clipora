from app.services.resolver_errors import NoDirectMediaError, ResolverError, UnsupportedPlatformError, public_resolver_error


def test_resolver_errors_share_base_type():
    assert issubclass(UnsupportedPlatformError, ResolverError)
    assert issubclass(NoDirectMediaError, ResolverError)


def test_public_error_removes_ansi_and_caps_detail():
    error = RuntimeError("\x1b[0;31mERROR:\x1b[0m " + "failure " * 100)
    message = public_resolver_error(error)
    assert "\x1b" not in message
    assert not message.startswith("ERROR:")
    assert len(message) <= 360


def test_public_error_explains_tiktok_homepage_redirect():
    message = public_resolver_error(RuntimeError("ERROR: Unsupported URL: https://www.tiktok.com/?_r=1"))
    assert message.startswith("TikTok did not release")
