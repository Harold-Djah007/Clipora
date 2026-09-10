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
    assert message.startswith("TikTok did not return a public video")


def test_public_error_explains_empty_tiktok_failure():
    message = public_resolver_error(ValueError("yt-dlp could not extract media from this tiktok link. "))
    assert "Open the post in TikTok" in message


def test_public_error_explains_instagram_extract_failure():
    message = public_resolver_error(ValueError("yt-dlp could not extract media from this instagram link."))
    assert message.startswith("Instagram did not return")


def test_public_error_explains_threads_failure():
    message = public_resolver_error(ValueError("Threads did not return a public photo or video for this link."))
    assert message.startswith("Threads did not return")


def test_public_error_empty_text_still_has_fallback():
    message = public_resolver_error(RuntimeError("ERROR:"))
    assert message == "The resolver could not extract downloadable media from this link."
